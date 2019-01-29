------------------------------- MODULE carousel -------------------------------

(***************************************************************************)
(* This is a TLA+ specification of the Carousel protocol.                  *)
(***************************************************************************)

\* References:
\*    Hillel Wayne - Practical TLA+ (https://books.google.ca/books/about/Practical_TLA+.html)
\*    Hillel Wayne - Learn TLA (https://learntla.com)
\*    Leslie Lamport - A PlusCal User's Manual (https://lamport.azurewebsites.net/tla/p-manual.pdf)
\*    Leslie Lamport - Specifying Systems (https://lamport.azurewebsites.net/tla/book.html)

\* GitHub:
\*    belaban/pluscal (https://github.com/belaban/pluscal) - simple constructs built with TLA+ and PlusCal
\*    muratdem/PlusCal-examples (https://github.com/muratdem/PlusCal-examples) - protocol models

\* Overview:
\* A client-server model with a set of "Clients" and another set of "Nodes"
\*      with in and out message channels (implemented as unbounded queues)
\*      to transmit messages and responses between the two sets
\* There are 2 concurrent processes in this spec: 
\*   1. A client process for each Client, which nondeterministically selects a subset of 
\*      the Nodes, populates the Nodes' respective in channels with messages.
\*      In addition, the client process contains a block that processes messages/responses
\*      sent by the Nodes back to the Client: it retrieves the transaction ID of the message
\*      and check if all the Nodes targeted by that transaction ID have responded
\*   2. A receiver process for each Node, which dequeues its in channel, processes the message,
\*      updates the Node's status, and sends a response (with a status nondeterministically 
\*      determined as either Abort or Commit) back to the Node that sent the message.

\* Temporal properties and correctness invariants should be put after the "END TRANSLATION" line

EXTENDS Naturals, FiniteSets, Sequences, TLC

\* C, N are defined in the TLC model
\* C = Number of Clients
\* N = Number of Nodes
CONSTANT C, N, IDSet
ASSUME C \in Nat /\ C > 0
ASSUME N \in Nat /\ N > 0

\* Clients and Nodes as sets
Clients == [type: {"C"}, num: 1..C]
Nodes == [type: {"N"}, num: 1..N]

\* Beginning of PlusCal algorithm
(* --algorithm progress
\* PlusCal options (-termination)

variable
  \* Keep track of IDs already being used and processed
  usedIds = {},
  processedIds = {},
  
  \* in and out channels implemented as mappings between Nodes/Clients to their respective queues
  channels = [n \in Nodes |-> <<>>],
  inChannels = [c \in Clients |-> <<>>],

\* receiver process 
fair process nodeHandler \in Nodes
begin
    nodeHandlerStart:
    while TRUE do
        await channels[self] /= <<>> \/ processedIds = IDSet;
        if processedIds = IDSet then
            goto nodeHandlerEnd;
        end if;
        nodeProcess:
        with msg = Head(channels[self]) do
            with status \in {"Committed", "Aborted"} do
                inChannels[msg.client] := Append(inChannels[msg.client], [id |-> msg.id, serverStatus |-> status, node |-> self]);
            end with;
        end with;
        channels[self] := Tail(channels[self]); 
    end while;
    nodeHandlerEnd:
    skip;
end process;



\* sender process
fair process clientHandler \in Clients
variable
    expectedRemaining,
    currentMsg,
    chosenSubset;
begin
  clientStart:
  while usedIds /= IDSet do
    with id \in IDSet \ usedIds do
        with sub \in SUBSET Nodes \ {{}} do
            currentMsg := [id |-> id, client |-> self];
            chosenSubset := sub;
            expectedRemaining := Cardinality(sub);
            usedIds := usedIds \cup {id};
        end with;
    end with;
    
    \* Send message to every server chosen
    sendLoop:
    while chosenSubset /= {} do
        with server \in chosenSubset do
            channels[server] := Append(channels[server], currentMsg);
            chosenSubset := chosenSubset \ {server};
        end with;
    end while;
    
    receiveLoop:
    while expectedRemaining > 0 do
        await inChannels[self] /= <<>>;
        with msg = Head(inChannels[self]) do
            assert msg.id = currentMsg.id;
        end with;
        inChannels[self] := Tail(inChannels[self]);
        expectedRemaining := expectedRemaining - 1;
    end while;
    
    setProcessed:
    processedIds := processedIds \cup {currentMsg.id};
  end while;
end process;

end algorithm *)
\* BEGIN TRANSLATION
CONSTANT defaultInitValue
VARIABLES usedIds, processedIds, channels, inChannels, pc, expectedRemaining, 
          currentMsg, chosenSubset

vars == << usedIds, processedIds, channels, inChannels, pc, expectedRemaining, 
           currentMsg, chosenSubset >>

ProcSet == (Nodes) \cup (Clients)

Init == (* Global variables *)
        /\ usedIds = {}
        /\ processedIds = {}
        /\ channels = [n \in Nodes |-> <<>>]
        /\ inChannels = [c \in Clients |-> <<>>]
        (* Process clientHandler *)
        /\ expectedRemaining = [self \in Clients |-> defaultInitValue]
        /\ currentMsg = [self \in Clients |-> defaultInitValue]
        /\ chosenSubset = [self \in Clients |-> defaultInitValue]
        /\ pc = [self \in ProcSet |-> CASE self \in Nodes -> "nodeHandlerStart"
                                        [] self \in Clients -> "clientStart"]

nodeHandlerStart(self) == /\ pc[self] = "nodeHandlerStart"
                          /\ channels[self] /= <<>> \/ processedIds = IDSet
                          /\ IF processedIds = IDSet
                                THEN /\ pc' = [pc EXCEPT ![self] = "nodeHandlerEnd"]
                                ELSE /\ pc' = [pc EXCEPT ![self] = "nodeProcess"]
                          /\ UNCHANGED << usedIds, processedIds, channels, 
                                          inChannels, expectedRemaining, 
                                          currentMsg, chosenSubset >>

nodeProcess(self) == /\ pc[self] = "nodeProcess"
                     /\ LET msg == Head(channels[self]) IN
                          \E status \in {"Committed", "Aborted"}:
                            inChannels' = [inChannels EXCEPT ![msg.client] = Append(inChannels[msg.client], [id |-> msg.id, serverStatus |-> status, node |-> self])]
                     /\ channels' = [channels EXCEPT ![self] = Tail(channels[self])]
                     /\ pc' = [pc EXCEPT ![self] = "nodeHandlerStart"]
                     /\ UNCHANGED << usedIds, processedIds, expectedRemaining, 
                                     currentMsg, chosenSubset >>

nodeHandlerEnd(self) == /\ pc[self] = "nodeHandlerEnd"
                        /\ TRUE
                        /\ pc' = [pc EXCEPT ![self] = "Done"]
                        /\ UNCHANGED << usedIds, processedIds, channels, 
                                        inChannels, expectedRemaining, 
                                        currentMsg, chosenSubset >>

nodeHandler(self) == nodeHandlerStart(self) \/ nodeProcess(self)
                        \/ nodeHandlerEnd(self)

clientStart(self) == /\ pc[self] = "clientStart"
                     /\ IF usedIds /= IDSet
                           THEN /\ \E id \in IDSet \ usedIds:
                                     \E sub \in SUBSET Nodes \ {{}}:
                                       /\ currentMsg' = [currentMsg EXCEPT ![self] = [id |-> id, client |-> self]]
                                       /\ chosenSubset' = [chosenSubset EXCEPT ![self] = sub]
                                       /\ expectedRemaining' = [expectedRemaining EXCEPT ![self] = Cardinality(sub)]
                                       /\ usedIds' = (usedIds \cup {id})
                                /\ pc' = [pc EXCEPT ![self] = "sendLoop"]
                           ELSE /\ pc' = [pc EXCEPT ![self] = "Done"]
                                /\ UNCHANGED << usedIds, expectedRemaining, 
                                                currentMsg, chosenSubset >>
                     /\ UNCHANGED << processedIds, channels, inChannels >>

sendLoop(self) == /\ pc[self] = "sendLoop"
                  /\ IF chosenSubset[self] /= {}
                        THEN /\ \E server \in chosenSubset[self]:
                                  /\ channels' = [channels EXCEPT ![server] = Append(channels[server], currentMsg[self])]
                                  /\ chosenSubset' = [chosenSubset EXCEPT ![self] = chosenSubset[self] \ {server}]
                             /\ pc' = [pc EXCEPT ![self] = "sendLoop"]
                        ELSE /\ pc' = [pc EXCEPT ![self] = "receiveLoop"]
                             /\ UNCHANGED << channels, chosenSubset >>
                  /\ UNCHANGED << usedIds, processedIds, inChannels, 
                                  expectedRemaining, currentMsg >>

receiveLoop(self) == /\ pc[self] = "receiveLoop"
                     /\ IF expectedRemaining[self] > 0
                           THEN /\ inChannels[self] /= <<>>
                                /\ LET msg == Head(inChannels[self]) IN
                                     Assert(msg.id = currentMsg[self].id, 
                                            "Failure of assertion at line 113, column 13.")
                                /\ inChannels' = [inChannels EXCEPT ![self] = Tail(inChannels[self])]
                                /\ expectedRemaining' = [expectedRemaining EXCEPT ![self] = expectedRemaining[self] - 1]
                                /\ pc' = [pc EXCEPT ![self] = "receiveLoop"]
                           ELSE /\ pc' = [pc EXCEPT ![self] = "setProcessed"]
                                /\ UNCHANGED << inChannels, expectedRemaining >>
                     /\ UNCHANGED << usedIds, processedIds, channels, 
                                     currentMsg, chosenSubset >>

setProcessed(self) == /\ pc[self] = "setProcessed"
                      /\ processedIds' = (processedIds \cup {currentMsg[self].id})
                      /\ pc' = [pc EXCEPT ![self] = "clientStart"]
                      /\ UNCHANGED << usedIds, channels, inChannels, 
                                      expectedRemaining, currentMsg, 
                                      chosenSubset >>

clientHandler(self) == clientStart(self) \/ sendLoop(self)
                          \/ receiveLoop(self) \/ setProcessed(self)

Next == (\E self \in Nodes: nodeHandler(self))
           \/ (\E self \in Clients: clientHandler(self))
           \/ (* Disjunct to prevent deadlock on termination *)
              ((\A self \in ProcSet: pc[self] = "Done") /\ UNCHANGED vars)

Spec == /\ Init /\ [][Next]_vars
        /\ \A self \in Nodes : WF_vars(nodeHandler(self))
        /\ \A self \in Clients : WF_vars(clientHandler(self))

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION

\* Invariants
\*StatusInvariant == \A x \in 1..N:
\*                status[x] = "Committed" \/ status[x] = "Aborted" \/ status[x] = "Prepared" \/ status[x] = "Initiated"
\*                
\*SentReceivedInvariant == \A x \in 1..N:
\*                sent[x] <= NumOfMessages /\ received[x] <= NumOfMessages /\ sent[x] < received[x]
\*                
\*\* Correctness
\*CounterCorrectness == <>(Termination /\ (\A x \in 1..N: sent[x] = NumOfMessages /\ received[x] = NumOfMessages))

=================================
