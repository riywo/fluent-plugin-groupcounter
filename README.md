# fluent-plugin-groupcounter

Fluentd plugin to count like SELECT COUNT(\*) GROUP BY.

## Configuration

Assume inputs are coming as followings:

    apache.access: {"code":"200", "method":"GET", "path":"/index.html", "reqtime":"1.001" }
    apache.access: {"code":"202", "method":"GET", "path":"/foo.html",   "reqtime":"2.002" }
    apache.access: {"code":"200", "method":"GET", "path":"/index.html", "reqtime":"3.003" }

Think of quering `SELECT COUNT(\*) GROUP BY code,method,path`. Configuration becomes as below:

    <match apache.access>
      type groupcounter
      aggregate tag
      output_per_tag true
      add_tag_prefix groupcounter
      group_by_keys code,method,path
    </match>

Output becomes like

    groupcounter.apache.access: {"200_GET_/index.html_count":2, "202_GET_/foo.html_count":1}

## Parameters

* group\_by\_keys (semi-required)

    Specify keys in the event record for grouping. `group_by_keys` or `group_by_expression` is required.

* delimiter

    Specify the delimiter to join `group_by_keys`. Default is '_'.

* pattern\[1-20\]

    Use `patternX` option to apply grouping more roughly. For example, adding a configuration for the above example as below

         pattern1 2xx ^2\d\d

    gives you an ouput like

         groupcounter.apache.access: {"2xx_GET_/index.html_count":3}

* group\_by\_expression (semi-required)

    Use an expression to group the event record. `group_by_keys` or `group_by_expression` is required.

    For examples, for the exampled input above, the configuration as below

        group_by_expression ${method}${path}/${code}

    gives you an output like

        groupcounter.apache.access: {"GET/index.html/200_count":1, "GET/foo.html/400_count":1}

    SECRET TRICK: You can write a ruby code in the ${} placeholder like

        group_by_expression ${method}${path.split(".")[0]}/${code[0]}xx

    This gives an output like

        groupcounter.apache.access: {"GET/index/2xx_count":1, "GET/foo/4xx_count":1}

* tag

    The output tag. Default is `groupcount`.

* add\_tag\_prefix

    The prefix string which will be added to the input tag. `output_per_tag yes` must be specified together. 

* remove\_tag\__prefix

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

    For examples, for the exampled input above, adding the configuration as below

        max_key reqtime

    gives you an output like

        groupcounter.apache.access: {"200_GET_/index.html_reqtime_max":3.003, "202_GET_/foo.html_reqtime_max":2.002}

* min\_key

    Specify key name in the event record to do `SELECT COUNT(\*),MIN(key_name) GROUP BY`.

* avg\_key

    Specify key name in the event record to do `SELECT COUNT(\*),AVG(key_name) GROUP BY`.

* count\_suffix

    Default is `_count`

* max\_suffix

    Default is `_max`. Should be used with `max_key` option.

* min\_suffix

    Default is `_min`. Should be used with `min_key` option.

* avg\_suffix

    Default is `_avg`. Should be used with `avg_key` option.

## ChangeLog

See [CHANGELOG.md](CHANGELOG.md) for details.

## Contributing

1. Fork it
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create new [Pull Request](../../pull/new/master)

## Copyright

* Copyright
  * Copyright (c) 2012- Ryosuke IWANAGA (riywo)
  * Copyright (c) 2013- Naotoshi SEO (sonots)
* License
  * Apache License, Version 2.0
