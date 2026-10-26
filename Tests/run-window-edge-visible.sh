#!/bin/bash
# Disabled after independent safety review: globally posted HID drag may leave
# the left mouse button down or reach another window. Do not launch the fixture.
printf '%s\n' 'SKIP 77: synthetic global-pointer edge drag is disabled pending a provably safe harness; use a human hand-test on an isolated candidate.'
exit 77
