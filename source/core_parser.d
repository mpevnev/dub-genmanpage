/* Core parser module

   A core parser is responsible for reading a list of commands from 
   'dub --help' and rendering 'dub.1' manpage.

   */

module core_parser;

final class CoreParser
{
    import std.stdio;

    private:
        File manpage;

    public:

        this()
        {
            import std.exception;

            try {
                manpage = File("dub.1", "w");
            } catch (ErrnoException e) {
                import core.stdc.stdlib;
                writef("Error opening 'dub.1': %s\n", e.msg);
                exit(1);
            }
        }

        /* Parse DUB's output, write manpage to the file. */
        void run()
        {
            import parsed.extras;

            import common;
            import command_parser;

            auto text = helpOutput;
            auto state = ParserState!string(text);

            /* Write the header. */
            manpage.writeln(".TH DUB \"1\"");
            manpage.writeln(".SH NAME");
            manpage.writeln(r"dub \- a package manager and build system for D programming language");
            manpage.writeln();

            /* Write the synopsis */
            manpage.writeln(".SH SYNOPSIS");
            manpage.writeln(".B dub");
            state = synopsis(false).run(state);
            assert(state.success);
            manpage.writeln(state.value);

            /* Write the description. */
            state = manpage.writeDescription(state);

            /* Collect the list of commands. */
            state = sectionSeparator(true).run(state);
            manpage.writeln(state.value);
            manpage.writeln("Each of the following commands also has a separate manpage.");
            string[] commands;

            import std.string;

            auto subsection = line!string(false)
                % ((res, s) => r"\-\- " ~ s.strip ~ r" \-\-")
                / someWhite!string(true)
                / many(1, -1, literal!string("-"))
                / many(-1, -1, newline!string);
            /* We need unmodified command name as well as a line it appears in. */
            struct Cmd
            {
                string command;
                string line;

                Cmd setCmd(string s) { auto res = this; res.command = s; return res; }
                Cmd setLine(string s) { auto res = this; res.line = s; return res; }
            }
            /* Lines where a new command appears are indented by two spaces. */
            auto cmdLine = many(2, -1, literal!Cmd(" "))
                / test!Cmd((res, s) => s.length == 2)
                / word!Cmd(Word.any)
                % ((res, s) => res.setCmd(s))
                % ((res, s) => res.setLine(s.makeBold.slashHyphens ~ " "))
                / someWhite!Cmd
                / many(0, -1, 
                        absorb!(Cmd, string)(
                            ((cmd, box, s) => cmd.setLine(cmd.line ~ box)),
                            anyBoxed(true))
                        % ((res, s) => res.setLine(res.line ~ " "))
                        / someWhite!Cmd(true))
                % ((res, s) => res.setLine(res.line ~ '\n'))
                / line!Cmd(false)
                % ((res, s) => res.setLine(res.line ~ s.strip))
                / many(-1, -1, newline!Cmd);
            auto continueDescr = line!string(false)
                % ((res, s) => s.strip)
                / many(-1, -1, newline!string);
            auto sep = sectionSeparator(true);
            while (true) {
                /* Check for a subsection. */
                auto maybeSubsection = subsection.run(state);
                if (maybeSubsection.success) {
                    manpage.writeln("\n.PP");
                    manpage.writeln(maybeSubsection.value);
                    manpage.writeln();
                    state = maybeSubsection;
                    continue;
                }

                /* Chech for a new command. */
                string absorber(string str, Cmd cmd, string s)
                {
                    commands ~= cmd.command;
                    return cmd.line;
                }
                auto p = absorb!(string, Cmd)(&absorber, cmdLine);
                auto maybeCommand = p.run(state);
                if (maybeCommand.success) {
                    /* Write a new command. */
                    manpage.writeln(".TP");
                    manpage.writeln(maybeCommand.value);
                    state = maybeCommand;
                    continue;
                }

                /* Check for the end of section. */
                auto maybeSeparator = sep.run(state);
                if (maybeSeparator.success) {
                    manpage.writeln(maybeSeparator.value);
                    state = maybeSeparator;
                    break;
                }

                /* Must be a continuation of a command line. */
                state = continueDescr.run(state);
                manpage.writeln(state.value);
            } /* white true */

            /* Write the options. */
            manpage.writeln();
            state = options.run(state);
            assert(state.success);
            manpage.writeln(state.value);

            /* Write FILES section. */
            manpage.writeFiles();

            /* Write SEE ALSO section. */
            manpage.writeln();
            manpage.writeln(".SH SEE ALSO");
            foreach (cmd; commands) 
                manpage.write(r"\fIdub-", cmd, r"\fR(1), ");
            manpage.write(r"\fIdub.json\fR(5), \fIdub.sdl\fR(5)");

            /* Generate command-specific manpages. */
            foreach (cmd; commands) {
                auto parser = new CommandParser(cmd);
                parser.run(commands);
            }
        } /* run */

    private:

        /* Collect DUB's help message. */
        string helpOutput()
        {
            import core.stdc.stdlib;
            import std.process;
            import std.string;

            try {
                auto msg = execute(["dub", "--help"]);
                return msg.output;
            } catch (ProcessException e) {
                writef("Error spawning a process: %s\n", e.msg);
                exit(1);
            } catch (StdioException e) {
                writef("Error capturing output: %s\n", e.msg);
                exit(1);
            }
            /* Should be unreachable. */
            assert(false);
        }
}
