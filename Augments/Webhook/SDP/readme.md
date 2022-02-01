**How to Install**
 1. Download the attached .zip file
 2. Extract the attached .zip file
 3. Verify contents includes:
	 1. File: webhook_sdp.pipe
	 2. Folder: Webhook_SDP
		 a. File: augment.jq
		 b. File: augmentation.root
		 c. File: entry.jq
		 d. File: lib.jq
		 e. File: README.md
		 f. File: whsdp.jq
4. Transfer the webhook_sdp.pipe file to the Open Collector
5. Run the following commands to import the Webhook Pipeline Augmentation
	1.  cat webhook_sdp.pipe | ./lrctl oc pipe augment import
	2. ./lrctl metrics restart
	3. ./lrctl oc restart
6. Submit data to your augmented pipeline



A means to run step 5 as a single command is possible through the following:
*cat webhook_sdp.pipe | ./lrctl oc pipe augment import && ./lrctl oc restart*
