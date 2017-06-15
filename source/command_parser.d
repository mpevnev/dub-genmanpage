/* Command parser module

   A command parser is responsible for rendering its command manpage. 

   */

module command_parser;

final class CommandParser
{
    import std.stdio;

    private:
        File manpage;
        string cmd;

    public:

        this(string cmd)
        {
            import std.exception;

            this.cmd = cmd;

            string filename = "dub-" ~ cmd ~ ".1";
            try {
                manpage = File(filename, "w");
            } catch (ErrnoException e) {
                import core.stdc.stdlib;
                writef("Error opening '%s': %s\n", filename, e.msg);
                exit(1);
            }
        }

        /* Parse DUB's output, write manpage to the file. */
        void run(string[] otherCmds)
        {
            import common;

            auto text = helpOutput;
            auto state = ParserState(text);

            /* Write the header. */
            manpage.writeln(".TH DUB-", cmd, " \"1\"");
            manpage.writeln(".SH NAME");
            manpage.writeln(r"dub\-", cmd, r" \- "); /* This would have to be
                                                        filled manually. */

            /* Write the synopsis. */
            manpage.writeln(".SH SYNOPSIS");
            manpage.writeln(".B dub-", cmd);
            state = synopsis!char.run(state);
            manpage.writeln(state.returnValue);
            manpage.writeln();

            /* Write the description. */
            state = manpage.writeDescription(state);

            /* Write the options. */
            state = options!char.run(state);
            manpage.writeln(state.returnValue);

            /* Write FILES section. */
            manpage.writeFiles();

            /* Write SEE ALSO section. */
            manpage.writeln();
            manpage.writeln(".SH SEE ALSO");
            manpage.write(r"\fIdub\fR(1), ");
            foreach (command; otherCmds) {
                if (cmd == command) continue;
                manpage.write(r"\fIdub-", command, r"\fR(1), ");
            }
            manpage.write(r"\fIdub.json\fR(5), \fIdub.sdl\fR(5)");

        }

    private:

        /* Collect DUB's help message. */
        string helpOutput()
        {
            import core.stdc.stdlib;
            import std.process;
            import std.string;

            try {
                auto msg = execute(["dub", cmd, "--help"]);
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
