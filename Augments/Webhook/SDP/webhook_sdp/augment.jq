import "./whsdp.jq" as WHSDP;

def check_whgen($message):
    if $message.whsdp == true then
        true
    elif ($message.whsdp | length) > 0 then
        true
    else
        false
    end
;

# augment your pipeline for additional transforms logic
def augment:
    (.input.message? | fromjson ) // null as $message |
    # If the input data has the field 'whsdp' defined and contains any data or equal to true
    # then the source defined parsing augmentation will be applied.  Otherwise no changes are made.
    if check_whgen($message) then WHSDP::sdp($message) else . end |
    .
;

