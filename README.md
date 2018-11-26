## connect.pl

### Description

Quick network service checker (commandline output like "top").

### Usage

#### connect.pl

```
USAGE:  connect.pl [ OPTIONS ] <address:port> [ <address:port> ... ]

  -v, --verbose         show more information
  -l, --syslog          send output to syslog, too
  -t, --timeout=<i>     set TCP timeout to <i> seconds [default=2]
  -r, --rtt=<i>         wait for <i> seconds between connections [default=3]
  -b, --batchmode       no clear screen, between rounds
  -c, --count           stop after <i> executions
```

#### connect2.pl

```
Besides <address:port> you can check the following services:

  <address>:ping	pings <address>
  <address>:dns=<query>	tries to lookup <query> via dns lookup
  <address>:smtp=<port>	tries a smtp connect
  <address>:http[s]	tries a http(s) connect
```

### License

None. Use it for free.

