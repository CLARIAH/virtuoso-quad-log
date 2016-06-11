

CREATE PROCEDURE vql_assert_configuration() {

    if (cfg_item_value(virtuoso_ini_path(), 'Parameters', 'CheckpointAuditTrail') = '0') {
        --This will end this procedure.
        signal('99999', ': CheckpointAuditTrail is not enabled. This will cause me to miss updates. Therefore I will not run!');
    }
}

CREATE PROCEDURE vql_create_nquad(in op any, in s any, in p any, in o any, in g any) {

    return(concat(op, ' ',
        vql_format_iri(s), ' ',
        vql_format_iri(p), ' ',
        vql_format_object(o), ' ',
        vql_format_iri(g), ' .'));
}

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
        result := concat('"', __ro2sq(object), '"');
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
