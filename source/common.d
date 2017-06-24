/* Common module

   Provides routines common to both core and command parsers.

   */

import std.string;

import parsed.extras;

/* ---------- modifiers ---------- */

auto
makeBold(string s)
{
    return r"\fB" ~ s ~ r"\fR";
}

auto
makeItalicized(string s)
{
    return r"\fI" ~ s ~ r"\fR";
}

auto 
slashHyphens(string s)
{
    import std.regex;
    auto regex = ctRegex!"-";
    return s.replaceAll(regex, r"\-");
}

auto
makeUppercase(string s)
{
    import std.string;
    return s.toUpper;
}

/* ---------- parsers ---------- */

/* (--|-)name[=value]. Makes name and hyphens bold and value italicized. */
auto
option(bool replace = false)
{
    import std.uni;

    return many(1, -1, literal!string("-"))
        * charWhile!string(
                c => !c.isWhite && c != ']' && c != '>' && c != '=',
                false)
        / morph!string(s => s.slashHyphens.makeBold)
        % ((res, name) => replace ? name : res ~ name)
        / maybe(
                literal!string("=")
                % ((res, eq) => res ~ eq)
                / word!string(Word.any)
                % ((res, w) => res ~ w.slashHyphens.makeItalicized)
               );
}

/* <something>. Makes it uppercased and italicized. */
auto
argument(bool replace = false)
{
    return literal!string("<")
        / charWhile!string(x => x != '>', false)
        * many(0, -1, literal!string("."))
        / literal!string(">").discard
        * maybe(many(3, -1, literal!string(".")))
        / morph!string(s => s.makeUppercase.makeItalicized)
        % ((res, s) => replace ? s : res ~ s);
}

/* SOMETHING. Makes it italicized. */
auto 
value(bool replace = false)
{
    return charWhile!string(x => 'A' <= x && x <= 'Z', false)
        / morph!string(s => s.makeItalicized)
        % ((res, val) => replace ? val : res ~ val);
}

/* [something] or [<something>]. */
auto
boxed(bool replace = false)
{
    return literal!string("[")
        % ((res, s) => replace ? "[" : res ~ '[')
        / (argument | option)
        / literal!string("]")
        % ((res, s) => res ~ ']');
}

/* Either <something> or [something] or [<something> [something-else]]. */
auto
anyBoxed(bool replace = false)
{
    auto nested = 
        literal!string("[")
        % ((res, s) => replace ? "[" : res ~ '[')
        / (argument | option)
        / maybeWhite!string(false)
        % ((res, s) => s.length > 0 ? res ~ ' ' : res)
        / boxed
        / literal!string("]")
        % ((res, s) => res ~ ']');
    return argument(replace) | boxed(replace) | nested;
}

/* ["]dub. Makes it bold. */
auto
dub(bool replace = false)
{
    return build!string((res, na) => replace ? "" : res)
        / maybe(
                literal!string("\"")
                % (res, quote) => res ~ quote)
        / literal!string("dub")
        % ((res, d) => res ~ d.makeBold);
}

/* A word. */
auto
prettyWord(bool replace = false, bool doBoldify = false)
{
    auto justAWord =
        word!string(Word.any)
        % ((res, w) => doBoldify ? 
                res ~ w.slashHyphens.makeBold :
                res ~ w.slashHyphens);
    return maybeWhite!string(true)
        % ((res, s) => replace ? "" : res)
        / (dub | argument | option | justAWord)
        / many(-1, -1, whitespace!string(true))
        % (res, s) => res ~ ' ';
}

/* Options block. */
auto
options()
{
    import std.string;

    auto oneName = option 
        % ((res, s) => res ~ ' ')
        / maybeWhite!string(true);
    auto allNames = maybeWhite!string
        % ((res, s) => res ~ "\n.TP\n")
        / many(1, -1, oneName)
        % ((res, s) => res ~ '\n')
        / maybeWhite!string;
    /* To work with lists, we need to know starting indentation. */
    struct List 
    {
        size_t indent;
        string text;
        List setIndent(size_t to) { auto res = this; res.indent = to; return res; }
        List addText(string str) { auto res = this; res.text ~= str; return res; }
    }
    import std.conv;
    auto list = line!List(false)
        / test!List((res, s) => s.strip.endsWith(":"))
        % ((res, s) => res.setIndent(s.whitePrefix))
        % ((res, s) => res.addText(s.strip ~ "\n.nf\n"))
        / repeatWhile!List((res, s, i) => s.whitePrefix > res.indent,
                line!List(false)
                % ((res, s) => res.addText(s.strip ~ '\n')))
        % ((res, s) => res.addText(".fi\n"));
    auto absorbList = absorb!(string, List)(
            (res, lst, s) => res ~ lst.text,
            list);
    auto descr = line!string(false)
        / test!string((res, s) => !s.startsWith("DUB")) /* version line. */
        % ((res, s) => res ~ ' ' ~ s.strip ~ ' ')
        / maybe(someNewlines!string);
    auto section = sectionSeparator(false);
    return build!string((res, s) => "")
        / many(0, -1, section | allNames | absorbList | descr);
}

/* A section separator - two lines, the second is many '='s. */
auto
sectionSeparator(bool replace = false)
{
    return line!string(true)
        / morph!string(s => "\n.SH " ~ s.makeUppercase)
        % ((res, s) => replace ? s : res ~ s)
        / many(2, -1, literal!string("="))
        / maybeWhite!string(true);
}

/* Parse synopsis. */
auto
synopsis(bool commandGiven)
{
    auto white = maybeWhite!string(false);
    if (commandGiven)
        return literal!string("USAGE: dub") 
            / white
            / maybe(prettyWord(false, true))
            / white
            / many(0, -1, anyBoxed / white % (res, s) => res ~ ' ');
    else
        return literal!string("USAGE: dub")
            / white
            / many(0, -1, anyBoxed / white % (res, s) => res ~ ' ');
}

/* ---------- not parsers, just convenience functions ---------- */

import std.stdio;

/* And also write next section's title. */
ParserState!string
writeDescription(File manpage, ParserState!string state)
{
    state = maybeWhite!string(true).run(state);
    manpage.writeln("\n.SH DESCRIPTION");
    auto w = prettyWord(true, false);
    auto sep = sectionSeparator(true);
    state = state.succeed;
    ParserState!string old;
    while (state.success) {
        old = state;
        state = sep.run(state);
        if (state.success) {
            manpage.writeln();
            return old;
        }

        state = w.run(old);
        if (state.success) {
            manpage.write(state.value);
        }
    }
    manpage.writeln();
    return old;
}

void
writeFiles(File manpage)
{
    manpage.writeln();
    manpage.writeln(".SH FILES");
    manpage.writeln("dub.sdl, dub.json");
}

/* Returns the number of leading spaces. */
size_t
whitePrefix(string str)
{
    import std.uni;

    size_t res = 0;
    size_t len = str.length;
    while (res < len && str[res].isWhite) res++;
    return res;
}
