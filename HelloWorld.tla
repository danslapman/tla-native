---- MODULE HelloWorld ----
\* Comprehensive trace spec: exercises Naturals, Integers, Sequences, FiniteSets, TLC
\* so their tlc2.module.* Java classes get captured in the reflection config.
EXTENDS Naturals, Integers, Sequences, FiniteSets, TLC

VARIABLES x, seq, s

Init ==
  /\ x = 0
  /\ seq = << 1, 2, 3 >>
  /\ s = {1, 2}

Next ==
  /\ x < 1
  /\ x' = x + 1
  /\ seq' = Append(seq, x + 4)
  /\ s' = s \union {x + 3}

Inv ==
  /\ x \in 0..10
  /\ Len(seq) <= 10
  /\ Cardinality(s) <= 10

Spec == Init /\ [][Next]_<<x, seq, s>>

====
