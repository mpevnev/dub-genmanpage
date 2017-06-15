/* Main module

   Responsible for instantiating and running parsers.

   */

void main()
{
    import core_parser;

    auto core = new CoreParser();
    core.run();
}
