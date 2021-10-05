# Augmenting Pipelines

Augmentation is the process of taking an existing LR pipeline and making additional schema based modifications for additive or subtractive purposes. Logs currently go through a transformative process (JQ transforms) before being converted to syslog and sent to the Agent. JQ augmentation is an optional stage that occurs after the JQ transforms. You can augment the log after it has gone through transforms to see desired parsing improvements.

The diagram below explains the workflow:

```             
  +---------------+   +-----------------+   +-------------------+
  | JQ Transforms |-->| JQ Augmentation |-->| Syslog Conversion |
  +---------------+   +-----------------+   +-------------------+
```

* Transforms -> Log goes through LR based parsing
* Augmentation -> Your custom augmentation
* Syslog Conversion -> Log is converted to syslog format

## Additional Resources

* JQ documentation: https://stedolan.github.io/jq/manual/

* For more detailed information on pipeline augmentation, please review the official docs on our community page.
