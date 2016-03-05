class Parsing extends mohxa.Mohxa {

    public function new() {
        super();

        describe('hxml basic', function() {

            var hxml = '-main Tests\n-x run_tests\n-lib mohxa';
            var res = tides.parse.HXML.parse(hxml);
            log(res);
            it('should parse correctly', function() {
                notequal(res, null);
                equalint(res.length, 6);
                equal(res[0], '-main');
                equal(res[1], 'Tests');
                equal(res[2], '-x');
                equal(res[3], 'run_tests');
                equal(res[4], '-lib');
                equal(res[5], 'mohxa');
            });

        });

    } //new

} //Parsing