json-logging-eap6: Example application showing how to alter the configuration to use JSON logging
=================================================================================================

What is it?
-----------

This example demonstrates how to enable the existing JSON logging formatter in the current EAP image.  There are two modifications from the standard standalone-openshift.xml

1. Change the named formatter to OPENSHIFT
2. Include the printDetails property within the OPENSHIFT formatter to include the source class name, source file name, source method name and source line number.

Running the Example
-------------------

This example can be deployed by executing the following commands, the template 

oc process -f eap64-basic-s2i.json -v SOURCE_REPOSITORY_URL=https://github.com/knrc/openshift-examples.git,SOURCE_REPOSITORY_REF=json-logging-eap6,CONTEXT_DIR=json-logging-eap6 | oc create -f -
