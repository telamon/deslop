#!/bin/sh
# Fake HARNESS_BIN (raw variant): consumes stdin, emits a canned
# /v1/systemone SystemOneResponse (draft ex. 2; choice tags).
cat > /dev/null
echo '{"model":"fake-one","answers":{'
echo '"line_1":{"type":"choice","choice":"awesomesauce"},'
echo '"line_2":{"type":"choice","choice":"mediocre"},'
echo '"line_3":{"type":"choice","choice":"typesafe"},'
echo '"line_4":{"type":"choice","choice":"mediocre"},'
echo '"line_5":{"type":"choice","choice":"awesomesauce"},'
echo '"line_6":{"type":"choice","choice":"typesafe"},'
echo '"line_7":{"type":"choice","choice":"typesafe"}},'
echo '"usage":{"input_tokens":0,"output_tokens":0}}'
