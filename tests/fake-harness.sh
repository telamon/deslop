#!/bin/sh
# Fake HARNESS_BIN (raw variant): consumes stdin, emits a canned
# /v1/systemone SystemOneResponse (draft ex. 1; noul = (fitness+1)/2).
cat > /dev/null
echo '{"model":"fake-one","answers":{'
echo '"line_1":{"type":"noul","noul":1.0},'
echo '"line_2":{"type":"noul","noul":0.5},'
echo '"line_3":{"type":"noul","noul":0.945},'
echo '"line_4":{"type":"noul","noul":0.56},'
echo '"line_5":{"type":"noul","noul":1.0},'
echo '"line_6":{"type":"noul","noul":1.0},'
echo '"line_7":{"type":"noul","noul":1.0}},'
echo '"usage":{"input_tokens":0,"output_tokens":0}}'
