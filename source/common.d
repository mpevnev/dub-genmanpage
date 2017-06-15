/* Common module

   Provides routines common to both core and command parsers.

   */

import std.string;
import std.traits;
import std.uni;

import std.stdio;

/* ---------- base classes and structures ---------- */

struct ParserState
{
    string left;
    string returnValue;
    string[string] saved; /* Saved return values. */
    bool success = true;

    this(string toParse)
    {
        left = toParse;
        returnValue = null;
    }

    ParserState fail() 
    { 
        success = false; 
        returnValue = null;
        return this;
    }

    ParserState succeed(string retVal) 
    { 
        success = true;
        returnValue = retVal;
        return this;
    }

    ParserState succeed()
    {
        success = true;
        /* No change to return value. */
        return this;
    }

    ParserState save(string as)
    {
        saved[as] = returnValue;
        return this;
    }

    bool empty()
    {
        return left == "";
    }

    string opIndex(string name)
    {
        return saved[name];
    }

    void opAssign(ParserState rhs)
    {
        left = rhs.left;
        returnValue = rhs.returnValue;
        success = rhs.success;
        saved = rhs.saved.dup;
    }
}

interface Parser
{
    ParserState run(ParserState toParse);
    alias ownRun = run;

    final ParserState run(string text)
    {
        return run(ParserState(text));
    }

    /* Return true if the parser succeeds on the text. */
    final bool match(string text)
    {
        auto res = run(text);
        return res.success;
    }

    /* ---------- operations on parsers ---------- */

    /* Feed this parser's output to the second one. */
    final Parser chain(Parser other, bool collect)
    {
        class Res: Parser
        {
            ParserState run(ParserState toParse)
            {
                ParserState old = toParse;
                auto res1 = this.outer.run(toParse);
                auto res2 = other.run(res1);
                if (res1.success && res2.success) {
                    if (collect) {
                        return res2.succeed(res1.returnValue ~ res2.returnValue);
                    } else {
                        if (res2.returnValue is null)
                            return res2.succeed(res1.returnValue);
                        else
                            return res2.succeed();
                    }
                } else {
                    return old.fail;
                }
            } /* run */
        } /* Res */
        return new Res();
    } /* chain */

    /* Try two parsers in parralel. */
    final Parser any(Parser other)
    {
        class Res: Parser
        {
            ParserState run(ParserState toParse)
            {
                ParserState old = toParse;
                auto res = this.outer.run(toParse);
                if (res.success) return res.succeed;
                return other.run(res);
            }
        }
        return new Res();
    }

    /* Send parser's return value into /dev/null. */
    final Parser discard()
    {
        class Res: Parser
        {
            ParserState run(ParserState toParse)
            {
                ParserState res = this.outer.run(toParse);
                if (res.success)
                    return res.succeed(null);
                else
                    return res.fail;
            }
        }
        return new Res();
    }

    /* ---------- operator overloads ---------- */

    /* Chain discarding first output. Think of '/' as a wall where flow stops. */
    final Parser opBinary(string op)(Parser other)
        if (op == "/")
    {
        return chain(other, false);
    }

    /* Chain collecting first output. Think of '*' as a piece of chain. */
    final Parser opBinary(string op)(Parser other)
        if (op == "*")
    {
        return chain(other, true);
    }

    /* Infix analog of 'any' */
    final Parser opBinary(string op)(Parser other)
        if (op == "|")
    {
        return any(other);
    }
}

/* ---------- literal parsers ---------- */

/* Parses a literal string (case-insensitive by default), returns parsed
   string.
   */
auto
literal(string str, bool ignoreCase = true)
{
    string use = str;
    if (ignoreCase) use = use.toLower;
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            string checkAgainst = toParse.left;
            if (ignoreCase) checkAgainst = checkAgainst.toLower;
            if (checkAgainst.startsWith(use)) {
                toParse.left = toParse.left[use.length .. $];
                return toParse.succeed(str);
            }
            return toParse.fail;
        }
    }
    return new Res();
}

/* Checks for a string literal without returning it. Search is case-insensitive
   by default).
   */
auto
check(string str, bool ignoreCase = true)
{
    string use = str;
    if (ignoreCase) use = use.toLower;
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            string checkAgainst = toParse.left;
            if (ignoreCase) checkAgainst = checkAgainst.toLower;
            if (checkAgainst.startsWith(use)) {
                toParse.left = toParse.left[use.length .. $];
                return toParse.succeed;
            }
            return toParse.fail;
        }
    }
    return new Res();
}

/* Drops specified string literal from the input (case-insensitive by default),
   returns previous return value. Does nothing if the input doesn't start with
   given string.
   */
auto
skip(string str, bool ignoreCase = true)
{
    string use = str;
    if (ignoreCase) use = use.toLower;
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            string checkAgainst = toParse.left;
            if (ignoreCase) checkAgainst = checkAgainst.toLower;
            if (checkAgainst.startsWith(use)) {
                toParse.left = toParse.left[str.length .. $];
                return toParse.succeed();
            }
            return toParse.succeed();
        }
    }
    return new Res();
}

/* ---------- produce ---------- */

/* A parser that always succeeds with given return value. */
auto
produce(string str)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            return toParse.succeed(str);
        }
    }
    return new Res();
}

/* ---------- parsers for working with memory ---------- */

/* A parser that saves current return value. */
auto
save(string as)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            return toParse.save(as);
        }
    }
    return new Res();
}

/* A parser that returns a saved return value. */
auto
load(string name)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            return toParse.succeed(toParse.saved[name]);
        }
    }
    return new Res();
}

/* A parser that clears a saved return value. */
auto
forget(string name)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            if (name in toParse.saved)
                toParse.saved.remove(name);
            return toParse.succeed();
        }
    }
    return new Res();
}

/* A parser that succeeds if there's a saved return value with given name. */
auto
recall(string name)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            if (name in toParse.saved)
                return toParse.succeed;
            else
                return toParse.fail;
        }
    }
    return new Res();
}

/* ---------- conditional parsers ---------- */

/* Collects characters while a condition is met. Always succeeds */
auto
collectWhile(T)(bool delegate (T) test, bool keepTerminator = true) if (isSomeChar!T)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            size_t i = 0;
            while (i < toParse.left.length && test(toParse.left[i]))
                i++;
            string res;
            if (keepTerminator && (i + 1) < toParse.left.length) {
                res = toParse.left[0 .. i + 1];
                toParse.left = toParse.left[i + 1 .. $];
            } else {
                res = toParse.left[0 .. i];
                toParse.left = toParse.left[i .. $];
            }
            return toParse.succeed(res);
        }
    }
    return new Res();
}

/* Collects characters until a condition is met. Always succeeds */
auto
collectUntil(T)(bool delegate (T) test, bool keepTerminator = true) if (isSomeChar!T)
{
    return collectWhile!T(x => !test(x), keepTerminator);
}

/* Collects until the end of line. */
auto
collectLine(T)(bool keepTerminator = true) if (isSomeChar!T)
{
    return collectWhile!T(x => x != '\n' && x != '\r', keepTerminator);
}

/* Drops a line, newline included. */
auto 
dropLine(T)() if (isSomeChar!T)
{
    return collectLine!T(true).discard;
}

/* Drops characters until a condition is met. Returns previous return value. */
auto
dropUntil(T)(bool delegate (T) test, bool keepTerminator = true) if (isSomeChar!T)
{
    return collectUntil!T(test, keepTerminator).discard;
}

/* Drops characters while a condition is met. Returns previous return value. */
auto
dropWhile(T)(bool delegate (T) test, bool keepTerminator = true) if (isSomeChar!T)
{
    return collectWhile!T(test, keepTerminator).discard;
}

/* Drops or collects whitespace. In 'stopOnNewline' mode does not collect the
   newline char. Always succeeds. */
auto
whitespace(T)(bool drop = true, bool stopOnNewline = false) if (isSomeChar!T)
{
    if (drop) 
        if (stopOnNewline)
            return dropWhile!T(x => x != '\n' && x != '\r' && isWhite(x), false);
        else
            return dropWhile!T(x => isWhite(x), false);
    else 
        if (stopOnNewline)
            return collectWhile!T(x => x != '\n' && x != '\r' && isWhite(x), false);
        else
            return collectWhile!T(x => isWhite(x), false);
}

/* Collects until first whitespace character. Always succeeds. */
auto
nonwhite(T)() if (isSomeChar!T)
{
    return collectUntil!T(x => isWhite(x), false);
}

/* Succeeds if previous return value passes the test. */
auto
test(bool delegate(string) check)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            if (check(toParse.returnValue))
                return toParse.succeed;
            else
                return toParse.fail;
        }
    }
    return new Res();
}

/* ---------- misc ---------- */

/* Uses the same parser between 'min' and 'max' times. If either of 'min' and
   'max' is negative, there's no limit on corresponding number of times. 
   Concatenates each run's output into single string.
   */
auto
many(Parser p, int min, int max)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            string res = null;
            ParserState original = toParse;

            ParserState cur = p.run(toParse);
            /* Check required minimum of successful parses. */
            if (min > 0) {
                int n = 0;
                while (n < min && cur.success) {
                    res ~= cur.returnValue;
                    cur = p.run(cur);
                    n++;
                }
                if (n < min) return original.fail;
            }

            /* Parse the rest. */
            int n = 0;
            while ((max < 0 || (max > 0 && n < max)) && cur.success) {
                res ~= cur.returnValue;
                cur = p.run(cur);
                n++;
            }
            return cur.succeed(res);
        }
    }
    return new Res();
}

/* Uses parser 0 or 1 times. */
auto
maybe(Parser p)
{
    return many(p, 0, 1);
}

/* Performs a function on the return value of the last parser. Fails if
   previous parser has failed or produced no output.
   */
auto
mutate(string delegate (string) mutation)
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            if (!toParse.success) return toParse.fail;
            if (toParse.returnValue is null) return toParse.fail;
            return toParse.succeed(mutation(toParse.returnValue));
        }
    }
    return new Res();
}

/* A parser that always fails. */
auto 
fail()
{
    class Res: Parser
    {
        ParserState run(ParserState toParse)
        {
            return toParse.fail;
        }
    }
    return new Res();
}

/* ---------- concrete parsers for DUB ---------- */

/* Check that the string isn't empty (i.e. consists only of whitespace). */
auto
nonempty()
{
    import std.regex;
    auto regex = ctRegex!r"^\s*";
    return test(s => !s.matchFirst(regex).empty);
}

/* Strip whitespace. */
auto
strip()
{
    return mutate(s => std.string.strip(s));
}

/* Produce a space. */
auto
insertSpace()
{
    return produce(" ");
}

/* Produce a newline. */
auto
insertNewline()
{
    return produce("\n");
}

/* Make something bold. */
auto
bold()
{
    return mutate(s => r"\fB" ~ s ~ r"\fR");
}

/* Wrap something in italics. */
auto
italics()
{
    return mutate(s => r"\fI" ~ s ~ r"\fR");
}

/* Uppercase something */
auto
uppercase()
{
    return mutate(s => s.toUpper);
}

/* Prepend slashes to hyphens. */
auto
slashHyphens()
{
    import std.regex;
    auto hyphen = ctRegex!"-";
    return mutate(s => s.replaceAll(hyphen, r"\-"));
}

/* Literal dub should be bold. */
auto
dub()
{
    return literal("dub") / bold;
}

/* Either '--something' or '-something' (and optional '=SOMETHING-ELSE'. 
   Returns boldified string with hyphens slashed. 
 */
auto
option(T)()
{
    return many(literal("-"), 1, -1)
        * collectWhile!T(x => !x.isSpace 
                && x != ']' && x != '>' && x != '=' , 
                false)
        / bold
        * maybe(literal("=") * (nonwhite!T / italics))
        / slashHyphens;
}

/* <something> -> SOMETHING. */
auto
argument(T)()
{
    return check("<") 
        / collectUntil!T(x => x == '>', false)
        / check(">")
        * many(literal("."), 0, -1)
        / uppercase
        / italics;
}

/* SOMETHING -> (italics) SOMETHING. */
auto 
value(T)()
{
    return collectWhile!T(x => 'A' <= x && x <= 'Z', false) 
        / italics;
}

/* Either <something> or [something] or [<something>]. */
auto
box(T)()
{
    auto boxed = literal("[") * (argument!T | option!T) * literal("]");
    auto nested = literal("[") 
        * (argument!T | option!T)
        * whitespace!T(false) 
        * boxed 
        * literal("]");
    return argument!T | boxed | nested;
}

/* A word. */
auto
word(T)(bool doBoldify = false)
{
    auto justAWord = nonwhite!T / slashHyphens;
    if (doBoldify) 
        justAWord = justAWord / bold;
    return (dub | argument!T | option!T | justAWord) 
        * (whitespace!T * produce(" "));
}

/* Options block. Ends either with (something \n =======) or with DUB version
   line. A new section separator will result in a new section being inserted.
   */
auto
options(T)()
{
    auto newOption = produce("\n.TP\n")
        * whitespace!T
        * many(option!T / whitespace!T * insertSpace, 1, -1)
        / whitespace!T
        * insertNewline
        * collectLine!T;
    auto section = whitespace!char
        / collectLine!char
        / many(literal("="), 1, -1).discard
        / strip
        / mutate(s => ".SH " ~ s.toUpper ~ "\n\n");
    auto continueDescr = collectLine!char 
        / strip
        * insertSpace
        / test(s => !s.startsWith("DUB")) /* The last line is version info. */
        * insertNewline;
    return many(section | newOption | continueDescr, 0, -1);
}

/* Parse synopsis. */
auto
synopsis(T)()
{
    return check("USAGE: dub") 
        / maybe(word!T(true))
        / whitespace!char 
        / many(box!char / whitespace!char * insertSpace, 0, -1);
}

/* ---------- Not parsers, just convenience functions ---------- */

import std.stdio;

ParserState 
writeDescription(File manpage, ParserState state)
{
    auto separator = dropLine!char
        / whitespace!char
        / many(literal("="), 1, -1)
        / dropLine!char;

    manpage.writeln(".SH DESCRIPTION");
    auto w = word!char;
    while (!separator.match(state.left)) {
        state = w.run(state);
        manpage.write(state.returnValue);
    }
    manpage.writeln();
    return state;
}

void
writeFiles(File manpage)
{
    manpage.writeln();
    manpage.writeln(".SH FILES");
    manpage.writeln("dub.sdl, dub.json");
}
