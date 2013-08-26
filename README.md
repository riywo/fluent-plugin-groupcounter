# fluent-plugin-groupcounter

Fluentd plugin to count like COUNT(\*) GROUP BY

## Configuration

    <source>
      type tail
      path /var/log/httpd-access.log
      tag apache.access
      format apache
    </source>

    <match apache.access>
      type groupcounter
      count_interval 5s
      aggregate tag
      output_per_tag true
      tag_prefix groupcounter
      group_by_keys code,method,path
    </match>

Output like below

    groupcounter.apache.access: {"200_GET_/index.html_count":1,"200_GET_/index.html_rate":0.2,"200_GET_/index.html_percentage":100.0}

## Parameters

* group\_by\_keys (required)

    The target keys to group by in the event record.

* tag

    The output tag. Default is `datacount`.

* tag\_prefix

    The prefix string which will be added to the input tag. `output_per_tag yes` must be specified together. 

* input\_tag\_remove\_prefix

    The prefix string which will be removed from the input tag.

* count\_interval

    The interval time to count in seconds. Default is `60`.

* unit

    The interval time to monitor specified an unit (either of `minute`, `hour`, or `day`).
    Use either of `count_interval` or `unit`.

* output\_messages

    Specify `yes` if you want to get tested messages. Default is `no`.

## Copyright

* Copyright
  * Copyright (c) 2012- Ryosuke IWANAGA (riywo)
  * Copyright (c) 2013- Naotoshi SEO (sonots)
* License
  * Apache License, Version 2.0
