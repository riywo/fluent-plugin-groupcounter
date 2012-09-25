# fluent-plugin-groupcounter

## Component

### GroupCounterOutput

Fluentd plugin to count like COUNT(\*) GROUP BY

## Configuration

## GroupCounterOutput

    <source>
      type tail
      path /var/log/httpd-access.log
      tag apache.access
      format apache
    </source>

    <match apache.access>
      type groupcounter
      count_interval 60s
      aggregate tag
      output_per_tag true
      tag_prefix groupcounter
      group_by_keys code,method,path
    </match>

Output like below

    groupcounter.apache.access: {"200_GET_/index.html_count":1,"200_GET_/index.html_rate":0.2,"200_GET_/index.html_percentage":100.0}

## TODO

* tests
* documents

## Copyright

* Copyright
  * Copyright (c) 2012- Ryosuke IWANAGA (riywo)
* License
  * Apache License, Version 2.0
