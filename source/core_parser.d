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
            import common;
            import command_parser;

            auto text = helpOutput;
            auto state = ParserState(text);

            /* Write the header. */
            manpage.writeln(".TH DUB \"1\"");
            manpage.writeln(".SH NAME");
            manpage.writeln(r"dub \- a package manager and build system for D programming language");
            manpage.writeln();

            /* Write the synopsis */
            manpage.writeln(".SH SYNOPSIS");
            manpage.writeln(".B dub");
            state = synopsis!char.run(state);
            manpage.writeln(state.returnValue);
            manpage.writeln();

            /* Prepare section separator. */
            auto separator = dropLine!char
                / whitespace!char
                / many(literal("="), 1, -1)
                / dropLine!char;

            /* Write the description. */
            state = manpage.writeDescription(state);

            /* Collect the list of commands. */
            manpage.writeln(".SH COMMANDS");
            manpage.writeln("Each of the following commands also has a separate manpage.");
            manpage.writeln();
            string[] commands;
            state = separator.run(state); /* Jump over last section terminator. */

            auto subsection = collectLine!char(false)
                / strip
                / whitespace!char 
                / many(literal("-"), 3, -1).discard
                / dropLine!char;
            auto cmdLine = many(literal(" "), 2, -1)
                / test(s => s.length == 2)
                / nonwhite!char
                / save("cmd")
                / bold 
                / slashHyphens
                / whitespace!char
                * insertSpace
                * many(box!char * insertSpace / whitespace!char(true, true), 0, -1)
                * insertNewline
                * collectLine!char
                / strip
                / nonempty;
            auto continueDescr = collectLine!char / strip;
            while (!separator.match(state.left)) {
                auto newSubS = subsection.run(state);
                if (newSubS.success) {
                    /* Write a new subsection. */
                    manpage.writeln(".PP");
                    manpage.writeln(r"\-\- ", newSubS.returnValue, r" \-\-");
                    manpage.writeln;
                    state = newSubS;
                } else {
                    /* Write a new command or continue describing an old one. */
                    auto cmd = cmdLine.run(state);
                    if (cmd.success) {
                        manpage.writeln(".TP");
                        manpage.writeln(cmd.returnValue);
                        string command = cmd["cmd"];
                        commands ~= command;
                        state = cmd;
                    } else {
                        auto descr = continueDescr.run(state);
                        manpage.writeln(descr.returnValue);
                        state = descr;
                    }
                } /* if a new section */
            } /* while commands section */

            /* Write the options. */
            manpage.writeln();
            state = options!char.run(state);
            manpage.writeln(state.returnValue);

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
