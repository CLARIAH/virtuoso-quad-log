# Virtuoso Configuration

Configuration of your Virtuoso instance is critical in order to enable the quad_logger to do its work properly.
Virtuoso configuration is done in the ```virtuoso.ini``` file that comes with the Virtuoso distribution.

## Finding the virtuoso.ini file
If you are not sure where to find the ```viruoso.ini``` file on your system or which ```virtuoso.ini``` file is
used by your Virtuoso instance, here is how to find it.

### Connect to the Virtuoso Interactive SQL Interface
Open the Virtuoso Interactive SQL interface by typing ```isql``` on a command line.
```
1. # isql [host:port username password]
```
The parameters host, port, username and password are only necessary if you are logging in from a 
remote terminal. If the path to the ```isql``` executable is not set you may have to locate it first.
At a command line type
```
2. # find / -name isql
```
This will result in something like ```/usr/local/bin/isql```, the absolute path to your ```isql```
executable. Repeat the command after ```1.```, this time with the absolute path to the executable.

Alternatively you can use the HTML based Administration Console known as **Conductor** to open an interface
to the Interactive SQL (ISQL). The Administration Console can be reached by typing ```{host:port}/conductor```
in your browser, where ```host``` and ```port``` are respectively the HTTP server host name 
and port of your Virtuoso instance.

### The path to your virtuoso.ini file
The path to your active ```virtuoso.ini``` file is found by typing the following command at the SQL-prompt or 
in the Interactive SQL window.
```
select virtuoso_ini_path();
```
A typical outcome is ```/usr/local/var/lib/virtuoso/db/virtuoso.ini```.

## Critical configuration
Open the ```virtuoso.ini``` file in your favorite editor and verify and/or correct the following 
configuration settings. In the following the name of the configuration setting is preceded with
the name of the section [in square brackets] within the configuration file.

### [Database] TransactionFile
The absolute path to the transaction log file. The name of the file should start with ```virtuoso``` 
and end with ```.trx```.
```
TransactionFile	    = /usr/local/var/lib/virtuoso/db/virtuoso.trx
```
In your active ```virtuoso.ini``` file this parameter may point to the current transaction log file,
which has a date-time part in its name:
```
TransactionFile     = /usr/local/var/lib/virtuoso/db/virtuoso20160801075807.trx
```
The path to the directory of the transaction log files should be the same as the path to the 
```virtuoso.ini``` file or it should be listed in the configuration parameter **DirsAllowed**.

In interactive SQL you can find the path to the current transaction file by typing
```
SQL> select cfg_item_value(virtuoso_ini_path (), 'Database', 'TransactionFile');
```

### [Parameters] CheckpointInterval
The interval in minutes at which Virtuoso will automatically make a database checkpoint. This should be a
non-negative integer, greater than 0.
```
CheckpointInterval  = 60
```
After making a database checkpoint Virtuoso will start a new transaction log file. This will enable the
quad_logger to read the previous transaction log file and to parse mutations to a corresponding
```rdfpatch-{timestamp}``` file, where *timestamp* is the same for both patch and transaction log file.

In interactive SQL you can find the value of the CheckpointInterval parameter by typing
```
SQL> select cfg_item_value(virtuoso_ini_path (), 'Parameters', 'CheckpointInterval');
```

### [Parameters] CheckpointAuditTrail
The way Virtuoso handles checkpoints in regard to the audit trail. The value of this parameter should be
```1```. This guarantees that "*...a new log file will be generated in the old log file's directory 
with a name ending with the date and time of the new log file's creation.*"

In interactive SQL you can find the value of the CheckpointInterval parameter by typing
```
SQL> select cfg_item_value(virtuoso_ini_path (), 'Parameters', 'CheckpointAuditTrail');
```

## Non-critical configuration
The following settings of the ```virtuoso.ini``` file are not critical, but may be considered in 
order to ease or to enhance the behavior of the quad-logger.

### [Parameters] AutoCheckpointLogSize
The size of transaction log in bytes after which an automatic checkpoint is initiated. Transaction log files 
and rdfpatch files are coupled one-on-one. So the size of rdfpatch files ultimately is determined 
by the maximum size of transaction logs. Virtuoso may delay the setting of a checkpoint while large
transactions take place. This may result in huge transaction log files and consequently large
rdfpatch files. Setting this parameter to a reasonable value will prevent such unwanted behavior.

In interactive SQL you can find the value of the AutoCheckpointLogSize parameter by typing
```
SQL> select cfg_item_value(virtuoso_ini_path (), 'Parameters', 'AutoCheckpointLogSize');
```
If this parameter is not set the result of the previous query will be ```NULL```.

## More on configuration
A detailed description of the parameters in the configuration file ```virtuoso.ini``` can be found
at http://docs.openlinksw.com/virtuoso/dbadm.html .

## Restart the Virtuoso instance
After changing the ```virtuoso.ini``` file you will have to restart the Virtuoso instance in order
for the changes to take effect.

Locate the virtuoso executables on your system. These usually will be found in one of the ```bin```
directories. To locate the virtuoso-t executable you can use the Unix ```find``` command. On a
command line type
```
3. # find / -name virtuoso-t
```
The path to the virtuoso executable is for instance ```/usr/local/bin/virtuoso-t```. The ```isql``` 
executable will usually be found in the same directory. If in doubt find it with the same command.
```
4. # find / -name isql
```
The path to the executables found under ```3.``` and/or ```4.``` shall in the following be
referred to as ```VIRTUOSO_BIN```.

### Stopping the virtuoso server
In a Unix-distribution you can stop the server by connecting to the ISQL interactive interface and 
specifying the option ```-K```. This will shut down the virtuoso server on connecting to it.
```
# ${VIRTUOSO_BIN}/isql {host}:{port} {username} {password}  -K

The server is shutting down
```
The default server port is ```1111```. The server port is specified in the ```virtuoso.ini``` file
under ```[Parameters]```, ```ServerPort```.

### Starting the virtuoso server
In a Unix distribution you can start the virtuoso server by executing the following command
```
# ${VIRTUOSO_BIN}/virtuoso-t -f -c ${VIRTUOSO_INI}
```
where ```-f``` means run in the foreground and ```-c``` indicates the absolute path to your
```virtuoso.ini``` file. For other options see 
http://docs.openlinksw.com/virtuoso/dbadm.html#ch-server_01 under *switches for server for Unix platforms*.






