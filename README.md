# preamble

To play around with this image you need an openvirtuoso server. To help you get started you can create one using this image:

    docker run -d -p 8890:8890 --name virtuoso_server jauco/virtuoso-quad-log server

You can then browse to http://localhost:8890 and login with user: `dba` and password: `dba`.
You can upload data using the [quad store upload](http://localhost:8890/conductor/rdf_import.vspx)

# quickstart
Once you have a virtuoso container running you can run the quad-log like this:

	docker run -i -t --link virtuoso_server:virtuoso --name grabber jauco/virtuoso-quad-log

Or with any virtuoso server like this

	docker run -i -t -e="VIRTUOSO_ISQL_ADDRESS=127.0.01" -E="VIRTUOSO_ISQL_PORT=1111"  --name grabber jauco/virtuoso-quad-log

This initializes the container. You then rerun the container when needed:

	docker start -a grabber

Each time it runs it will output a new list of quads in the following format

	A <s> <p> <o> <g>
	A <s> <p> <o> <g>
	D <s> <p> <o> <g>
	# current position: 500

Make sure to set CheckpointAuditTrail=1 in the ini or else your transaction files will be emptied before the grabber might see them.

The container maintains the location in the log. So if you ever remove the container, you need to restart it with `-e "CURPOS=<last current position>"`.

# things to test and do

 - blank nodes
 - multiple trx files (after checkpointing has been run)
 - offsets with multiple trx files (is the offset global or file specific. How to handle the offset after a checkpoint has run. What if multiple checkpoints have run in between grabs)
 - strange characters in literals or hyperlinks. How to handle spaces.
 - make it a process that exposes its results in oai-rs instead logging a list to the console
 - check if CheckpointAuditTrail is enabled when running this logger
 - try multiple insertion strategies and see if we can trigger all cases in the log (LOG_INSERT, LOG_INSERT_SOFT etc.)
 - non-default literals (stuff tagged as a date for example)