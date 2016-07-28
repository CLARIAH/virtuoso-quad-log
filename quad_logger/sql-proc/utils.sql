
-- Assert that the Virtuoso server is configured as we expect.
CREATE PROCEDURE vql_assert_configuration() {

    if (cfg_item_value(virtuoso_ini_path(), 'Parameters', 'CheckpointAuditTrail') = '0') {
        signal('99999', ': CheckpointAuditTrail is not enabled. This will cause me to miss updates. Therefore I will not run!');
    }

    if (number(cfg_item_value(virtuoso_ini_path(), 'Parameters', 'CheckpointInterval')) < 1) {
        signal('99999', ': CheckpointInterval is disabled. Transaction log synchronisation will not be effective. Therefore I will not run!');
    }
    -- We get the CheckpointInterval as stated in virtuoso.ini.
    -- Automatic checkpointing can still be disabled, f.i. because SQL> checkpoint_interval (-1); was issued.
    -- We still miss that unwanted situation with above code.

    -- AutoCheckpointLogSize is another configuration parameter that could be inspected.
    -- Transaction log files and rdfpatch files are coupled one-on-one.
    -- So the size of rdfpatch files ultimately is determined by the maximum size of transaction logs.
}
;

-- Create an nquad from raw input, prefixed with an rdf-patch operand.
CREATE PROCEDURE vql_create_nquad(in op any, in s any, in p any, in o any, in g any) {

    return(concat(op, ' ',
        vql_format_iri(s), ' ',
        vql_format_iri(p), ' ',
        vql_format_object(o), ' ',
        vql_format_iri(g), ' .'));
}
;

-- turn the IRI in an encoded iri or a blank node
-- see also: 'IRI_ID Type' in http://docs.openlinksw.com/virtuoso/rdfdatarepresentation.html
CREATE PROCEDURE vql_format_iri (in iri any) {

    if (iri > min_64bit_bnode_iri_id()) {
        return concat('_:', ltrim(concat(iri, ''), '#'));
    } else {
        return concat('<', __ro2sq(iri), '>');
    }
}
;

-- turn the object part into an encoded literal or an iri
-- see also: 'Programatically resolving DB.DBA.RDF_QUAD.O to SQL'
-- in http://docs.openlinksw.com/virtuoso/rdfdatarepresentation.html
CREATE PROCEDURE vql_format_object (in object any) {

    declare result, objectType, languageTag any;

    if (isiri_id(object)) {
        return vql_format_iri(object);
    } else {
        result := concat('"', vql_escape_chars(__ro2sq(object)), '"');
        objectType := __ro2sq(DB.DBA.RDF_DATATYPE_OF_OBJ(object));
        languageTag := __ro2sq(DB.DBA.RDF_LANGUAGE_OF_OBJ(object));
        if (languageTag <> '') {
            result := concat(result, '@', languageTag);
        } else if (objectType <> '' and objectType <> 'http://www.w3.org/2001/XMLSchema#string') {
            result := concat(result, '^^<', objectType, '>');
        }
        return result;
    }
}
;

-- Uit https://www.w3.org/TR/n-quads/
-- Literals may not contain the characters ", LF, or CR. In addition '\' (U+005C) may not appear in any quoted literal
-- except as part of an escape sequence.
CREATE PROCEDURE vql_escape_chars(in str_ng any) {
    declare result any;
    result := regexp_replace(str_ng, '\x07', '\\\\a'); -- bell
    result := regexp_replace(result, '\x09', '\\\\t'); -- tab
    result := regexp_replace(result, '\x0A', '\\\\n'); -- line feed
    result := regexp_replace(result, '\x0C', '\\\\f'); -- form feed
    result := regexp_replace(result, '\x0D', '\\\\r'); -- carriage return
    result := regexp_replace(result, '\x1B', '\\\\e'); -- escape, not valid in quad store upload anyway
    -- not a control char but " should be escaped as well.
    result := regexp_replace(result, '\x22', '\\\\"'); -- escape double quotes
    return result;
}
;
