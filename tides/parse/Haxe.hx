package tides.parse;

import haxe.DynamicAccess;

import haxe.io.Path;

using StringTools;

class Haxe {

        /** Parse a composed haxe type (that can be a whole function signature)
            and return an object with all the informations walkable recursively (json-friendly)
            A function type will have an `args` value next to the `type` value
            while a regular type will only have a `type` value.
            In case the type is itself named inside another function signature, a `name` value
            Will be added to it. */
    public static function parse_composed_type(raw_composed_type:String, ?ctx:HaxeParseTypeContext):HaxeComposedType {

        var info:HaxeComposedType = {};
        var len = raw_composed_type.length;

        var current_item = '';
        var items = [];
        var item_params = [];
        var item:HaxeComposedType;
        var c, sub_item, params;

        if (ctx == null) {
            ctx = {
                i: 0, // index
                stop: null // the character that stopped the last recursive call
            };

                // Remove potential references to temporary package
                // TODO:
                //   if using tmp file method to perform autocomplete,
                //   remove the atom_tempfile__ references directly on the
                //   tmp file code instead. Removing it here is "too late"
            //raw_composed_type = raw_composed_type.split('atom_tempfile__.').join('');
        }

            // Iterate over each characters and parse groups recursively
        while (ctx.i < len) {
            c = raw_composed_type.charAt(ctx.i);

            if (c == '(') {
                ctx.i++;
                if (current_item.length > 0 && current_item.charAt(current_item.length - 1) == ':') {
                        // New group, continue parsing in a sub call until the end of the group
                    item = {
                        name: current_item.substring(0, current_item.length-1),
                        composed_type: parse_composed_type(raw_composed_type, ctx)
                    };
                    if (item.name.charAt(0) == '?') {
                        item.optional = true;
                        item.name = item.name.substring(1);
                    }
                    items.push(item);
                } else {
                    items.push(parse_composed_type(raw_composed_type, ctx));
                }
                current_item = '';
            }
            else if (c == '<') {
                ctx.i++;

                    // Add type parameters
                params = [];
                do {
                    params.push(parse_composed_type(raw_composed_type, ctx));
                }
                while (ctx.stop == ',');

                if (current_item.length > 0) {
                    item = parse_composed_type(current_item);

                    item.composed_type = {
                        params: params
                    };

                    if (item.type != null) {
                        item.composed_type.type = item.type;
                    }

                    if (item.composed_type != null) {
                        item.composed_type.composed_type = item.composed_type;
                    }

                    items.push(item);
                }
                item_params.push([]);
                current_item = '';
            }
            else if (c == '{') {
                    // Parse structure type
                if (current_item.length > 0 && current_item.charAt(current_item.length - 1) == ':') {
                    item = {
                        name: current_item.substring(0, current_item.length-1),
                        composed_type: parse_structure_type(raw_composed_type, ctx)
                    };
                    if (item.name.charAt(0) == '?') {
                        item.optional = true;
                        item.name = item.name.substring(1);
                    }
                    items.push(item);
                } else {
                    items.push(parse_structure_type(raw_composed_type, ctx));
                }
                current_item = '';
            }
            else if (c == ')') {
                ctx.i++;
                ctx.stop = ')';
                break;
            }
            else if (c == '>') {
                ctx.i++;
                ctx.stop = '>';
                break;
            }
            else if (c == ',') {
                ctx.i++;
                ctx.stop = ',';
                break;
            }
            else if (c == '-' && raw_composed_type.charAt(ctx.i + 1) == '>') {
                if (current_item.length > 0) {
                        // Parse the current item as a composed type in case there are
                        // nested groups inside
                    items.push(parse_composed_type(current_item));
                }
                current_item = '';
                ctx.i += 2;
            }
            else if (c.trim() == '') {
                ctx.i++;
            }
            else {
                current_item += c;
                ctx.i++;
            }
        }

            // Stopped by end of string
        if (ctx.i >= len) {
            ctx.stop = null;
        }

        if (current_item.length > 0) {
            if (current_item.indexOf('->') != -1) {
                    // Parse the current item as a composed type as there as still
                    // nested groups inside
                items.push(parse_composed_type(current_item));
            }
            else {
                items.push(parse_type(current_item));
            }
        }

        if (items.length > 1) {
                // If multiple items were parsed, that means it is a function signature
                // Extract arguments and return type
            info.args = [].concat(items);
            info.composed_type = info.args.pop();
            if (info.args.length == 1 && info.args[0].type == 'Void') {
                info.args = [];
            }
        }
        else if (items.length == 1) {
                // If only 1 item was parsed, this is a simple type
            info = items[0];
        }

        return info;

    } //parse_composed_type

        /** Parse structure type like {f:Int}
            Can be nested.
            Will update ctx.i (index) accordingly to allow
            a parent method to continue parsing of a bigger string */
    public static function parse_structure_type(raw_structure_type:String, ?ctx:HaxeParseTypeContext):HaxeComposedType {

        var item = new StringBuf();
        var len = raw_structure_type.length;
        var number_of_lts = 0;
        var c;

        if (ctx == null) {
            ctx = {
                i: 0 // index
            };
        }

        while (ctx.i < len) {
            c = raw_structure_type.charAt(ctx.i);

            if (c == '{') {
                number_of_lts++;
                ctx.i++;
                item.add(c);
            }
            else if (c == '}') {
                number_of_lts--;
                ctx.i++;
                item.add(c);
                if (number_of_lts <= 0) {
                    break;
                }
            }
            else if (c.trim() == '') {
                ctx.i++;
            }
            else if (number_of_lts == 0) {
                item.add('{}');
                break;
            }
            else {
                item.add(c);
                ctx.i++;
            }
        }

        return {
            type: item.toString()
        };

    } //parse_structure_type

        /** Parse haxe type / haxe named argument
            It will return an object with a `type` value
            or with both a `type` and `name` values */
    public static function parse_type(raw_type:String):HaxeComposedType {

        var parts = raw_type.split(':');
        var result:HaxeComposedType = {};

        if (parts.length == 2) {
            result.type = parts[1];
            result.name = parts[0];

        } else {
            result.type = parts[0];
        }

            // Optional?
        if (result.name != null && result.name.charAt(0) == '?') {
            result.optional = true;
            result.name = result.name.substring(1);
        }

        return result;

    } //parse_type

        /** Get string from parsed haxe type
            It may be useful to stringify a sub-type (group)
            of a previously parsed type */
    public static function string_from_parsed_type(parsed_type:HaxeComposedType):String {

        if (parsed_type == null) {
            return '';
        }

        var result;

        if (parsed_type.args != null) {
            var str_args;
            if (parsed_type.args.length > 0) {
                var arg_items = [];
                var str_arg;
                var i = 0;
                while (i < parsed_type.args.length) {
                    str_arg = string_from_parsed_type(parsed_type.args[i]);
                    if (parsed_type.args[i].args != null && parsed_type.args[i].args.length == 1) {
                        str_arg = '(' + str_arg + ')';
                    }
                    arg_items.push(str_arg);
                    i++;
                }
                str_args = arg_items.join('->');
            }
            else {
                str_args = 'Void';
            }

            if (parsed_type.composed_type != null) {
                if (parsed_type.composed_type.args != null) {
                    result = str_args + '->(' + string_from_parsed_type(parsed_type.composed_type) + ')';
                } else {
                    result = str_args + '->' + string_from_parsed_type(parsed_type.composed_type) + '';
                }
            } else {
                result = str_args + '->' + parsed_type.type;
            }
        }
        else {
            if (parsed_type.composed_type != null) {
                result = string_from_parsed_type(parsed_type.composed_type);
            } else {
                result = parsed_type.type;
            }
        }

        if (parsed_type.params != null && parsed_type.params.length > 0) {
            var params = [];
            var i = 0;
            while (i < parsed_type.params.length) {
                params.push(string_from_parsed_type(parsed_type.params[i]));
                i++;
            }

            result += '<' + params.join(',') + '>';
        }

        return result;

    } //string_from_parsed_type

        /** Try to match a partial function call or declaration from the given
            text and index position and return info if succeeded or null.
            Default behavior is to parse function call only.
            If an options argument is given with a `parse_declaration` key to true,
            it will instead only accept a signature which is a declaration (like `function foo(a:T, b|)`) */
    public static function parse_partial_signature(original_text:String, index:Int, ?options:ParsePartialSignatureOptions) {
            // Cleanup text
        var text = code_with_empty_comments_and_strings(original_text.substring(0, index));

        if (options == null) options = {};

        var i = index - 1;
        var number_of_args = 0;
        var number_of_parens = 0;
        var number_of_braces = 0;
        var number_of_lts = 0;
        var number_of_brackets = 0;
        var number_of_unclosed_parens = 0;
        var number_of_unclosed_braces = 0;
        var number_of_unclosed_lts = 0;
        var number_of_unclosed_brackets = 0;
        var signature_start = -1;
        var did_extract_used_keys = false;
        var c, arg;
        var partial_arg = null;

            // A key path will be detected when giving
            // anonymous structure as argument. The key path will allow to
            // know exactly which key or value we are currently writing.
            // Coupled with typedefs, it can allow to compute suggestions for
            // anonymous structure keys and values
        var can_set_colon_index = !options.parse_declaration;
        var colon_index = -1;
        var key_path = [];
        var used_keys = [];
        var partial_key = null;

        while (i > 0) {
            c = text.charAt(i);

            if (c == '"' || c == '\'') {
                    // Continue until we reach the beginning of the string
                while (i >= 0) {
                    i--;
                    if (text.charAt(i) == c) {
                        i--;
                        break;
                    }
                }
            }
            else if (c == ',') {
                if (number_of_parens == 0 && number_of_braces == 0 && number_of_lts == 0 && number_of_brackets == 0) {
                    can_set_colon_index = false;
                    number_of_args++;
                    if (partial_arg == null) {
                        partial_arg = original_text.substring(i + 1, index).ltrim();
                    }
                }
                i--;
            }
            else if (c == ')') {
                number_of_parens++;
                i--;
            }
            else if (c == '}') {
                number_of_braces++;
                i--;
            }
            else if (c == ']') {
                number_of_brackets++;
                i--;
            }
            else if (c == ':') {
                if (can_set_colon_index && number_of_braces == 0 && number_of_parens == 0 && number_of_lts == 0) {
                    colon_index = i;
                    can_set_colon_index = false;
                }
                i--;
            }
            else if (c == '{') {
                if (number_of_braces == 0) {
                        // Reset number of arguments because we found that
                        // all the already parsed text is inside an unclosed brace token
                    number_of_args = 0;
                    number_of_unclosed_braces++;

                    if (!options.parse_declaration) {
                        can_set_colon_index = true;

                        if (!did_extract_used_keys) {
                                // Extract already used keys
                            used_keys = extract_used_keys_in_structure(text.substring(i+1));
                            did_extract_used_keys = true;
                        }

                            // Match key
                        if (colon_index != -1) {
                            if (RE.ENDS_WITH_KEY.match(text.substring(0, colon_index + 1))) {
                                key_path.unshift(RE.ENDS_WITH_KEY.matched(1));
                            }
                        }
                        else if (key_path.length == 0) {
                            if (RE.ENDS_WITH_ALPHANUMERIC.match(text.substring(0, index))) {
                                partial_key = RE.ENDS_WITH_ALPHANUMERIC.matched(1);
                            } else {
                                partial_key = '';
                            }
                        }
                    }
                }
                else {
                    number_of_braces--;
                }
                i--;
            }
            else if (c == '(') {
                if (number_of_parens > 0) {
                    number_of_parens--;

                        // Ensure the unclosed brace is not a function body
                    if (number_of_parens == 0 && number_of_unclosed_braces > 0 && RE.ENDS_WITH_FUNCTION_KEYWORD.match(text.substring(0, i))) {
                            // In that case, this is not an anonymous structure
                        return null;
                    }

                    i--;
                }
                else {
                    if ((!options.parse_declaration && RE.ENDS_WITH_BEFORE_CALL_CHAR.match(text.substring(0, i)))
                    || (options.parse_declaration && RE.ENDS_WITH_BEFORE_SIGNATURE_CHAR.match(text.substring(0, i)))) {

                        if (RE.ENDS_WITH_FUNCTION_DEF.match(text.substring(0, i))) {
                            if (!options.parse_declaration) {
                                // Perform no completion on function definition signature
                                return null;
                            }
                        } else if (options.parse_declaration) {
                            return null;
                        }
                        number_of_args++;
                        signature_start = i;
                        if (partial_arg == null) {
                            partial_arg = original_text.substring(i + 1, index).ltrim();
                        }
                        break;
                    }
                    else {
                            // Reset number of arguments because we found that
                            // all the already parsed text is inside an unclosed paren token
                        number_of_args = 0;

                            // Reset key path also if needed
                        if (!options.parse_declaration) {
                            can_set_colon_index = true;
                            colon_index = -1;
                        }

                        number_of_unclosed_parens++;
                        i--;
                    }
                }
            }
            else if (number_of_parens == 0 && c == '>' && text.charAt(i - 1) != '-') {
                number_of_lts++;
                i--;
            }
            else if (number_of_parens == 0 && c == '<') {
                if (number_of_lts > 0) {
                    number_of_lts--;
                } else {
                        // Reset number of arguments because we found that
                        // all the already parsed text is inside an unclosed lower-than token
                    number_of_args = 0;

                        // Reset key path also if needed
                    can_set_colon_index = true;
                    colon_index = -1;

                    number_of_unclosed_lts++;
                }
                i--;
            }
            else if (c == '[') {
                if (number_of_brackets > 0) {
                    number_of_brackets--;
                } else {
                        // Reset number of arguments because we found that
                        // all the already parsed text is inside an unclosed lower-than token
                    number_of_args = 0;

                        // Reset key path also if needed
                    can_set_colon_index = true;
                    colon_index = -1;

                    number_of_unclosed_brackets++;
                }
                i--;
            }
            else {
                i--;
            }
        }

        if (signature_start == -1) {
            return null;
        }

        var result:HaxeParsedSignature = {
            signature_start: signature_start,
            number_of_args: number_of_args
        };

        if (!options.parse_declaration && number_of_unclosed_braces > 0) {
            result.key_path = key_path;
            result.partial_key = partial_key;
            result.used_keys = used_keys;
        }

            // Add partial arg, only if it is not empty and doesn't finish with spaces
        if (partial_arg != null && partial_arg.length > 0 && partial_arg.trim().length == partial_arg.length) {
            result.partial_arg = partial_arg;
        }

        return result;

    } //parse_partial_signature

        /* Find the position of the local declaration of the given identifier, from the given index.
           It will take care of searching in scopes that can reach the index (thus, ignoring declarations in other code blocks)
           Declarations can be:
            * var `identifier`
            * function `identifier`
            * function foo(`identifier`
            * function foo(arg1, `identifier`
            * ...
           Returns an index or -1 if nothing was found */
    public static function find_local_declaration(text:String, identifier:String, index:Int):Int {

            // Cleanup text
        text = code_with_empty_comments_and_strings(text);

        var i = index - 1;
        var number_of_args = 0;
        var number_of_parens = 0;
        var number_of_braces = 0;
        var number_of_lts = 0;
        var number_of_brackets = 0;
        var number_of_unclosed_parens = 0;
        var number_of_unclosed_braces = 0;
        var number_of_unclosed_lts = 0;
        var number_of_unclosed_brackets = 0;
        var c, m;
        var identifier_last_char = identifier.charAt(identifier.length - 1);
        var regex_identifier_decl = new EReg('(var|\\?|,|\\(|function)\\s*' + identifier + '$', '');

        while (i > 0) {
            c = text.charAt(i);

            if (c == '"' || c == '\'') {
                    // Continue until we reach the beginning of the string
                while (i >= 0) {
                    i--;
                    if (text.charAt(i) == c) {
                        i--;
                        break;
                    }
                }
            }
            else if (c == identifier_last_char) {
                if (number_of_braces == 0 && number_of_lts == 0 && number_of_brackets == 0) {
                    if (regex_identifier_decl.match(text.substring(0, i + 1))) {
                        m = regex_identifier_decl.matched(1);
                        if (m == '(' || m == '?'  || m == ',') {
                                // Is the identifier inside a signature? Ensure we are in a function declaration signature, not a simple call
                            var info = parse_partial_signature(text, i + 1, {parse_declaration: true});
                            if (info != null) {
                                    // Yes, return position
                                return i - identifier.length + 1;
                            }
                        } else {
                                // All right, the identifier has a variable or function declaration
                            return i - identifier.length + 1;
                        }
                    }
                }
                i--;
            }
            else if (c == ')') {
                number_of_parens++;
                i--;
            }
            else if (c == '}') {
                number_of_braces++;
                i--;
            }
            else if (c == ']') {
                number_of_brackets++;
                i--;
            }
            else if (c == '{') {
                if (number_of_braces == 0) {
                    number_of_unclosed_braces++;
                }
                else {
                    number_of_braces--;
                }
                i--;
            }
            else if (c == '(') {
                if (number_of_parens > 0) {
                    number_of_parens--;
                }
                else {
                    number_of_unclosed_parens++;
                }
                i--;
            }
            else if (number_of_parens == 0 && c == '>' && text.charAt(i - 1) != '-') {
                number_of_lts++;
                i--;
            }
            else if (number_of_parens == 0 && c == '<') {
                if (number_of_lts > 0) {
                    number_of_lts--;
                } else {
                    number_of_unclosed_lts++;
                }
                i--;
            }
            else if (c == '[') {
                if (number_of_brackets > 0) {
                    number_of_brackets--;
                } else {
                    number_of_unclosed_brackets++;
                }
                i--;
            }
            else {
                i--;
            }
        }

        return -1;

    } //find_local_declaration

        /** Return the given code after replacing single-line/multiline comments
            and string contents with white spaces. Also replaces strings in regex format (~/.../).
            In other words, the output will be the same haxe code, with the same text length
            but strings will be only composed of spaces and comments completely replaced with spaces
            Use this method to simplify later parsing of the code and/or make it more efficient
            where you don't need string and comment contents */
    public static function code_with_empty_comments_and_strings(input:String):String {

        var i = 0;
        var output = '';
        var len = input.length;
        var is_in_single_line_comment = false;
        var is_in_multiline_comment = false;
        var k;

        while (i < len) {

            if (is_in_single_line_comment) {
                if (input.charAt(i) == "\n") {
                    is_in_single_line_comment = false;
                    output += "\n";
                }
                else {
                    output += ' ';
                }
                i++;
            }
            else if (is_in_multiline_comment) {
                if (input.substr(i, 2) == '*/') {
                    is_in_multiline_comment = false;
                    output += '  ';
                    i += 2;
                }
                else {
                    if (input.charAt(i) == "\n") {
                        output += "\n";
                    }
                    else {
                        output += ' ';
                    }
                    i++;
                }
            }
            else if (input.substr(i, 2) == '//') {
                is_in_single_line_comment = true;
                output += '  ';
                i += 2;
            }
            else if (input.substr(i, 2) == '/*') {
                is_in_multiline_comment = true;
                output += '  ';
                i += 2;
            }
            else if (input.charAt(i) == '\'' || input.charAt(i) == '"') {
                if (RE.BEGINS_WITH_STRING.match(input.substring(i))) {
                    var match_len = RE.BEGINS_WITH_STRING.matched(0).length;
                    output += '"';
                    k = 0;
                    while (k < match_len - 2) {
                        output += ' ';
                        k++;
                    }
                    output += '"';
                    i += match_len;
                }
                else {
                        // Input finishes with non terminated string
                        // In that case, remove the partial string and put spaces
                    while (i < len) {
                        output += ' ';
                        i++;
                    }
                }
            }
            else if (input.charAt(i) == '~') {
                if (RE.BEGINS_WITH_REGEX.match(input.substring(i))) {
                    var match_len = RE.BEGINS_WITH_STRING.matched(0).length;
                    output += '~/';
                    k = 1;
                    while (k < match_len - 2) {
                        output += ' ';
                        k++;
                    }
                    output += '/';
                    i += match_len;
                }
                else {
                        // Input finishes with non terminated regex
                        // In that case, remove the partial regex and put spaces
                    while (i < len) {
                        output += ' ';
                        i++;
                    }
                }
            }
            else {
                output += input.charAt(i);
                i++;
            }
        }

        return output;

    } //code_with_empty_comments_and_strings

    public static function extract_used_keys_in_structure(cleaned_text:String):Array<String> {

        var i = 0, len = cleaned_text.length;
        var number_of_braces = 0;
        var number_of_parens = 0;
        var number_of_lts = 0;
        var number_of_brackets = 0;
        var c;
        var used_keys = [];

        while (i < len) {
            c = cleaned_text.charAt(i);
            if (c == '{') {
                number_of_braces++;
                i++;
            }
            else if (c == '}') {
                number_of_braces--;
                i++;
            }
            else if (c == '(') {
                number_of_parens++;
                i++;
            }
            else if (c == ')') {
                number_of_parens--;
                i++;
            }
            else if (c == '[') {
                number_of_brackets++;
                i++;
            }
            else if (c == ']') {
                number_of_brackets--;
                i++;
            }
            else if (c == '<') {
                number_of_lts++;
                i++;
            }
            else if (c == '>' && cleaned_text.charAt(i - 1) != '-') {
                number_of_lts--;
                i++;
            }
            else if (number_of_braces == 0 && number_of_parens == 0 && number_of_lts == 0 && number_of_brackets == 0) {
                if (RE.BEGINS_WITH_KEY.match(cleaned_text.substring(i))) {
                    i += RE.BEGINS_WITH_KEY.matched(0).length;
                    used_keys.push(RE.BEGINS_WITH_KEY.matched(0));
                }
                else {
                    i++;
                }
            } else {
                i++;
            }
        }

        return used_keys;

    } //extract_used_keys_in_structure

        /** Find the closest block starting from the given index.
            Returns the index or -1. */
    public static function index_of_closest_block(text:String, index:Int):Int {

        if (index == null) index = 0;

            // Cleanup text
        text = code_with_empty_comments_and_strings(text.substring(index));

        var i = 0;
        var len = text.length;
        var c;

        while (i < len) {
            c = text.charAt(i);

            if (c == '}') {
                return index + i;
            }
            else if (c == '{') {
                return index + i + 1;
            }

            i++;
        }

        return index + len - 1;

    } //index_of_closest_block

        /** Extract end of expression at the given index */
    public static function parse_end_of_expression(text:String, index:Int):String {
        if (index == null) index = 0;

            // Cleanup text
        var original_text = text;
        text = code_with_empty_comments_and_strings(text.substring(index));

        var i = 0;
        var len = text.length;
        var number_of_parens = 0;
        var m, c;
        var result = '';

        while (i < len) {
            c = text.charAt(i);

            if (c == '(') {
                if (RE.ENDS_WITH_BEFORE_CALL_CHAR.match(original_text.substring(0, index + i))) {
                    result += c;
                    break;
                }
                number_of_parens++;
                result += c;
                i++;
            }
            else if (c == ')') {
                result += c;
                if (number_of_parens > 0) {
                    number_of_parens--;
                    i++;
                } else {
                    break;
                }
            }
            else if (c == ';') {
                result += c;
                if (number_of_parens > 0) {
                    i++;
                } else {
                    break;
                }
            }
            else if (c == ',') {
                result += c;
                if (number_of_parens > 0) {
                    i++;
                } else {
                    break;
                }
            }
            else if (c.trim() == '') {
                result += c;
                if (number_of_parens > 0) {
                    i++;
                } else {
                    break;
                }
            }
            else {
                result += c;
                i++;
            }

        }

        return result;

    } //parse_end_of_expression

        /* Extract a mapping of imports
           From the given haxe code contents.
           Alias (in / as) are also parsed. */
    public static function extract_imports(input:String):DynamicAccess<Dynamic> {

            // Cleanup input
        input = code_with_empty_comments_and_strings(input);

        var imports:DynamicAccess<Dynamic> = {};

            // Run regexp
        RE.IMPORT.map(input, function(regex:EReg):String {
            var match1 = regex.matched(1);
            var match2 = regex.matched(2);
            if (match2 != null) {
                imports.set(match2, match1);
            } else {
                imports.set(match1, match1);
            }
            return '';
        });

        return imports;

    } //extract_imports

        /* Extract a package (as string)
           From the given haxe code contents.
           Default package will be an empty string */
    public static function extract_package(input:String):String {

        var i = 0;
        var len = input.length;
        var is_in_single_line_comment = false;
        var is_in_multiline_comment = false;
        var matches;

        while (i < len) {

            if (is_in_single_line_comment) {
                if (input.charAt(i) == "\n") {
                    is_in_single_line_comment = false;
                }
                i++;
            }
            else if (is_in_multiline_comment) {
                if (input.substr(i, 2) == '*/') {
                    is_in_multiline_comment = false;
                    i += 2;
                }
                else {
                    i++;
                }
            }
            else if (input.substr(i, 2) == '//') {
                is_in_single_line_comment = true;
                i += 2;
            }
            else if (input.substr(i, 2) == '/*') {
                is_in_multiline_comment = true;
                i += 2;
            }
            else if (input.charAt(i).trim() == '') {
                i++;
            }
            else if (RE.PACKAGE.match(input.substring(i))) {
                return RE.PACKAGE.matched(1);
            }
            else {
                    // Something that is neither a comment or a package token shown up.
                    // We are done
                return '';
            }
        }

        return '';

    } //extract_package

        /* Return the content after having detected and replaced the package name */
    public static function replace_package(input:String, new_package_name:String):String {

        var i = 0;
        var len = input.length;
        var is_in_single_line_comment = false;
        var is_in_multiline_comment = false;
        var matches;

        while (i < len) {

            if (is_in_single_line_comment) {
                if (input.charAt(i) == "\n") {
                    is_in_single_line_comment = false;
                }
                i++;
            }
            else if (is_in_multiline_comment) {
                if (input.substr(i, 2) == '*/') {
                    is_in_multiline_comment = false;
                    i += 2;
                }
                else {
                    i++;
                }
            }
            else if (input.substr(i, 2) == '//') {
                is_in_single_line_comment = true;
                i += 2;
            }
            else if (input.substr(i, 2) == '/*') {
                is_in_multiline_comment = true;
                i += 2;
            }
            else if (input.charAt(i).trim() == '') {
                i++;
            }
            else if (RE.PACKAGE.match(input.substring(i))) {
                    // Package detected. Replace it
                return input.substring(0, i) + 'package ' + new_package_name + input.substring(i + RE.PACKAGE.matched(0).length);
            }
            else {
                    // Something that is neither a comment or a package token shown up.
                    // No package in this file. Add the package at the beginning of the contents
                return "package " + new_package_name + ";\n" + input;
            }
        }

            // No package in this file. Add the package at the beginning of the contents
        return "package " + new_package_name + ";\n" + input;

    } //replace_package

        /** Parse haxe compiler output and extract info */
    public static function parse_compiler_output(output:String, ?options:ParseCompilerOutputOptions):Array<HaxeCompilerOutputElement> {

        if (options == null) {
            options = {};
        }

        var info:Array<HaxeCompilerOutputElement> = [];
        var prev_info = null;
        var lines = output.split("\n");
        var cwd = options.cwd;
        var line, line_str, file_path, location, start, end, message;
        var re = RE.HAXE_COMPILER_OUTPUT_LINE;

        for (i in 0...lines.length) {

            line_str = lines[i];

            if (info.length > 0) {
                prev_info = info[info.length - 1];
            }

            if (re.match(line_str)) {

                file_path = re.matched(1);
                line = Std.parseInt(re.matched(2));
                location = re.matched(3);
                start = Std.parseInt(re.matched(4));
                end = Std.parseInt(re.matched(5));
                message = re.matched(6);

                if (message != null || options.allow_empty_message) {

                        // Make file_path absolute if possible
                    if (cwd != null && !Path.isAbsolute(file_path)) {
                        file_path = Path.join([cwd, file_path]);
                    }

                    if (message != null
                        && prev_info != null
                        && prev_info.message != null
                        && prev_info.file_path == file_path
                        && prev_info.location == location
                        && prev_info.line == line
                        && prev_info.start == start
                        && prev_info.end == end) {
                            // Concatenate multiline message
                        prev_info.message += "\n" + message;
                    }
                    else {
                        info.push({
                            line: line,
                            file_path: file_path,
                            location: location,
                            start: start,
                            end: end,
                            message: message
                        });
                    }
                }
            }
        } //for lines

            // Prevent duplicate messages as this can happen, like multiple `Unexpected (` at the same location
            // We may want to remove this snippet in a newer haxe compiler version if the output is never duplicated anymore
        for (i in 0...info.length) {
            message = info[i].message;
            if (message != null) {
                var message_lines = message.split("\n");
                var all_lines_are_equal = true;
                if (message_lines.length > 1) {
                    line_str = message_lines[0];
                    for (l in 0...message_lines.length) {
                        if (line_str != message_lines[l]) {
                            all_lines_are_equal = false;
                            break;
                        }
                        line_str = message_lines[l];
                    }
                        // If all lines of message are equal, just keep one line
                    if (all_lines_are_equal) {
                        info[i].message = line_str;
                    }
                }
            }
        }

        return info;

    } //parse_compiler_output

} //Haxe


typedef HaxeComposedType = {
    @:optional var args:Array<HaxeComposedType>;
    @:optional var name:String;
    @:optional var optional:Bool;
    @:optional var type:String;
    @:optional var params:Array<HaxeComposedType>;
    @:optional var composed_type:HaxeComposedType;
}

typedef HaxeParseTypeContext = {
    var i:Int;
    @:optional var stop:String;
}

typedef ParsePartialSignatureOptions = {
        /** If set to true, function declarations will be parsed,
            instead of parsing function calls */
    @:optional var parse_declaration:Bool;
}

typedef HaxeParsedSignature = {

        /** The position of the opening parenthesis starting
            the function call signature */
    var signature_start:Int;

        /** The number of arguments between the signature
            start and the current position */
    var number_of_args:Int;

        /** An array of keys, in case the current position
            is inside an anonymous structure given as argument */
    @:optional var key_path:Array<String>;

        /** A string of the key being written at the current position
            if inside an anonymous structure given as argument */
    @:optional var partial_key:String;

        /** A string of the argument being written at the current position */
    @:optional var partial_arg:String;

        /** An array of keys, containing the keys already
            being used before the current position */
    @:optional var used_keys:Array<String>;
}

typedef ParseCompilerOutputOptions = {

    @:optional var allow_empty_message:Bool;

    @:optional var cwd:String;
}

typedef HaxeCompilerOutputElement = {

    var line:Int;

    var file_path:String;

    var location:String;

    var start:Int;

    var end:Int;

    var message:String;

}

@:allow(tides.parse.Haxe)
private class RE {

        /** Match any single/double quoted string */
    public static var BEGINS_WITH_STRING:EReg = ~/^(?:"(?:[^"\\]*(?:\\.[^"\\]*)*)"|'(?:[^'\\]*(?:\\.[^'\\]*)*)')/;
    public static var BEGINS_WITH_REGEX:EReg = ~/^~\/(?:[^\/\\]*(?:\\.[^\/\\]*)*)\//;
    public static var ENDS_WITH_BEFORE_CALL_CHAR:EReg = ~/[a-zA-Z0-9_\]\)]\s*$/;
    public static var ENDS_WITH_BEFORE_SIGNATURE_CHAR:EReg = ~/[a-zA-Z0-9_>]\s*$/;
    public static var ENDS_WITH_KEY:EReg = ~/([a-zA-Z0-9_]+)\s*:$/;
    public static var ENDS_WITH_ALPHANUMERIC:EReg = ~/([a-zA-Z0-9_]+)$/;
    public static var BEGINS_WITH_KEY:EReg = ~/^([a-zA-Z0-9_]+)\s*:/;
    public static var PACKAGE:EReg = ~/^package\s*([a-zA-Z0-9_]*(\.[a-zA-Z0-9_]+)*)/;
    public static var ENDS_WITH_FUNCTION_DEF:EReg = ~/[^a-zA-Z0-9_]function(?:\s+[a-zA-Z0-9_]+)?(?:<[a-zA-Z0-9_<>, ]+>)?$/;
    public static var ENDS_WITH_FUNCTION_KEYWORD:EReg = ~/[^a-zA-Z0-9_]function\s*$/;
    public static var IMPORT:EReg = ~/import\s*([a-zA-Z0-9_]+(?:\.[a-zA-Z0-9_]+)*)(?:\s+(?:in|as)\s+([a-zA-Z0-9_]+))?/g;
    public static var HAXE_COMPILER_OUTPUT_LINE:EReg = ~/^\s*(.+)?(?=\\:[0-9]*\\:)\\:([0-9]+)\\:\s+(characters|lines)\s+([0-9]+)\-([0-9]+)(?:\s+\\:\s*(.*?))?\s*$/;

} //RE
