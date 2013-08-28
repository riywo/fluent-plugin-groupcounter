# fluent-plugin-groupcounter

Fluentd plugin to count like SELECT COUNT(\*) GROUP BY.

## Configuration

Assume inputs are coming as followings:

    apache.access: {"code":"200", "method":"GET", "path":"/index.html", "foobar":"xxx" }
    apache.access: {"code":"404", "method":"GET", "path":"/not_found.html", "foobar":"xxx" }

Think of quering `SELECT COUNT(\*) GROUP BY code,method,path`. Configuration becomes as below:

    <match apache.access>
      type groupcounter
      count_interval 5s
      aggregate tag
      output_per_tag true
      tag_prefix groupcounter
      group_by_keys code,method,path
    </match>

Output becomes like

    groupcounter.apache.access: {"200_GET_/index.html_count":1, "404_GET_/not_found.html_count":1}

## Parameters

* group\_by\_keys

    The target keys to group by in the event record. Either of `group\_by\_keys` or `group\_by_placeholders` is required.

* group\_by\_placeholders

    The target expression to group by in the event record. Either of `group\_by\_keys` or `group\_by_placeholders` is required.
    Use this option when you want to customize the key values of output.

    For examples, for the exampled input above, the configuration as below

        group_by_placeholders ${method}${path}/${code}

    gives you an output like

        groupcounter.apache.access: {"GET/index.html/200_count":1, "GET/not_found.html/400_count":1}

    SECRET TRICK: You can write a ruby code in the ${} placeholder like

        group_by_placeholders ${method}${path.split(".")[0]}/${code}

    This gives an output like

        groupcounter.apache.access: {"GET/index/200_count":1, "GET/not_found/400_count":1}

* tag

    The output tag. Default is `groupcount`.

* tag\_prefix

    The prefix string which will be added to the input tag. `output_per_tag yes` must be specified together. 

* input\_tag\_remove\_prefix

    The prefix string which will be removed from the input tag.

* count\_interval

    The interval time to count in seconds. Default is `60`.

* unit

    The interval time to monitor specified an unit (either of `minute`, `hour`, or `day`).
    Use either of `count_interval` or `unit`.

* store\_file

    Store internal data into a file of the given path on shutdown, and load on starting.

* max\_key

    Specify key name in the event record to do `SELECT COUNT(\*),MAX(key_name) GROUP BY`.

* min\_key

    Specify key name in the event record to do `SELECT COUNT(\*),MIN(key_name) GROUP BY`.

* avg\_key

    Specify key name in the event record to do `SELECT COUNT(\*),AVG(key_name) GROUP BY`.

## Copyright

* Copyright
  * Copyright (c) 2012- Ryosuke IWANAGA (riywo)
  * Copyright (c) 2013- Naotoshi SEO (sonots)
* License
  * Apache License, Version 2.0
