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
            import parsed.extras;

            import common;

            auto text = helpOutput;
            auto state = ParserState!string(text);

            /* Write the header. */
            manpage.writeln(".TH DUB-", cmd, " \"1\"");
            manpage.writeln(".SH NAME");
            /* This would have to be filled manually. */
            manpage.writeln(r"dub\-", cmd, r" \- "); 

            /* Write the synopsis. */
            manpage.writeln(".SH SYNOPSIS");
            manpage.writeln(".B dub ");
            state = synopsis(true).run(state);
            assert(state.success);
            manpage.writeln(state.value);

            /* Write the description. */
            state = manpage.writeDescription(state);
            assert(state.success);

            /* Write the options. */
            manpage.writeln();
            state = options.run(state);
            manpage.writeln(state.value);

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
