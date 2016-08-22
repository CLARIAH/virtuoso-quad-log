-- This file follows procedure signatures of buffer_nquads.sql, making the files interchangeable.


-- Translate raw input into RDF-patch formatted N-Quads; subdivide N-Quads over graph iri, buffer N-Quads up to
-- maxq per graph iri, output N-Quads per graph when maxq has been reached.
--
-- This strategy does not buffer but sends quads immediately, preceded with header with each change of graph or
-- when maxq for current graph has been reached.
CREATE PROCEDURE vql_buffer_nquad(IN op ANY, IN raw_s ANY, IN raw_p ANY, IN raw_o ANY, IN raw_g ANY,
        IN buffer ANY, IN report ANY, IN at_checkpoint VARCHAR, IN maxq INT := 100000) {

    DECLARE qline, g_name, g_iri VARCHAR;

    g_iri := __ro2sq(raw_g);
    qline := vql_create_nquad(op, raw_s, raw_p, raw_o, raw_g);
    g_name := encode_base64(g_iri);

    if (g_name <> dict_get(buffer, 'last_name', 'nop') or dict_get(report, 'current_graph_quad_count', 0) > maxq) {
        dict_remove(report, 'current_graph_quad_count');
        dict_put(buffer, 'last_name', g_name);
        dict_inc_or_put(report, 'file_count', 1);

        dbg_printf('VQL: Sending new header for graph %s', g_iri);
        -- header
        result(concat('# at checkpoint  ', at_checkpoint));
        result(concat('# graph          ', g_iri));
        result(concat('# base64         ', g_name));
    }

    -- increase quad count in report
    dict_inc_or_put(report, 'quad_count', 1);
    -- keep track of quad count per graph
    dict_inc_or_put(report, 'current_graph_quad_count', 1);
    result(qline);
}


CREATE PROCEDURE vql_print_buffer(IN buffer ANY, IN report ANY, IN at_checkpoint VARCHAR) {

    -- nop. this procedure not realy needed in this strategy.
    DECLARE fcount INT;

    fcount := dict_get(report, 'file_count', 0);
    if (fcount > 0) {
        dbg_printf('VQL: End sending %d quads from checkpoint %s in %d files.', dict_get(report, 'quad_count', 0), at_checkpoint, fcount);
    }
}

CREATE PROCEDURE vql_print_graph(IN g_name STRING, IN g_vector ANY, IN at_checkpoint VARCHAR, IN report ANY) {

    -- nop. this procedure to make count of vql_* procedures complete.
    dbg_printf('VQL: This line will never be printed. %s', at_checkpoint);
}

