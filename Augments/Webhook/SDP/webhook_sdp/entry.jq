# DO NOT MODIFY THIS FILE
import "./augment.jq" as AUGMENT;
import "./lib.jq" as LIB;

LIB::augmented_io_format
|
AUGMENT::augment
|
.output.augmented = true
|
.output
