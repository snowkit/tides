
class Tests {

    static function main() {

        var run = new mohxa.Run([
            new Parsing()
        ]);

        Sys.println('completed ${run.total} tests, ${run.failed} failures (${run.time}ms)');
        Sys.println('');

    } //main

} //Tests