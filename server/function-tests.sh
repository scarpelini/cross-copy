#!/bin/bash

TEST="../cmd-client/cross-copy -q -l"

report(){
  
  echo "$@ in line" `caller 1`
}

assertEqual(){
  [[ "$1" == "$2" ]] || ( report "$3 (expected '$1' but was '$2')" && echo FAIL && exit 1 )
}

assertContains(){
  echo "$2" | grep "$1" > /dev/null || ( report "$3 ('$2' should contain '$1')" && echo FAIL && exit 1 )
}

##### FUNCTION TESTS

DEVICE_ID_1=`uuidgen`
DEVICE_ID_2=`uuidgen`
DATA="the message"
SECRET=`uuidgen`

function testSimpleTransfer(){
  echo $FUNCNAME
  ( M=`$TEST $SECRET`; assertEqual "$DATA" "$M" "should receive correct message" ) &
  sleep 1
  R=`$TEST $SECRET "$DATA"`
  assertEqual 1 $R "shoud have one direct delivery"
  SECRET=`uuidgen`
  wait
}

function testFetchingRecentPaste(){
  echo $FUNCNAME
  R=`$TEST $SECRET "$DATA"`
  assertEqual 0 $R "shoud have no direct deliverys"
  R=`$TEST -r $SECRET | grep -Po '"data":.*?[^\\\\]",'`
  assertEqual '"data":"the message",' "$R" "should get recently stored data"
  SECRET=`uuidgen`
}

function testFetchingTwoRecentPastes(){
  echo $FUNCNAME
  R=`$TEST -k 2 $SECRET "1"`
  R=`$TEST -k 1 $SECRET "2"`
  R=`$TEST -r $SECRET | grep -Po '"data":.*?[^\\\\]",'`
  assertEqual '"data":"1",
"data":"2",' "$R" "should get both messages"
  sleep 1
  R=`$TEST -r $SECRET | grep -Po '"data":.*?[^\\\\]",'`
  assertEqual '"data":"1",' "$R" "second message should have been kept for only a second"
  sleep 1
  R=`$TEST -r $SECRET | grep -Po '"data":.*?[^\\\\]",'`
  assertEqual '' "$R" "first message should have been kept for only two seconds"
  SECRET=`uuidgen`
}

function testFetchingRecentPasteInJsonFormatWithDeviceId(){
  echo $FUNCNAME
  R=`$TEST -d $DEVICE_ID_1 $SECRET "$DATA"`
  assertEqual 0 $R "shoud have no direct deliverys"
  R=`$TEST -j -d $DEVICE_ID_2 $SECRET`
  D=`echo "$R" | grep -Po '"data":.*?[^\\\\]",'`
  assertEqual '"data":"the message",' "$D" "should get recently stored data"
  assertContains "$DEVICE_ID_1" "$R" "should include id of sender"
  SECRET=`uuidgen`
}

function testWaitingForPasteAsJsonWithDeviceId(){
  echo $FUNCNAME
  ( M=`$TEST -j -d $DEVICE_ID_2 $SECRET | grep -Po '"data":.*?[^\\\\]",'`;   assertEqual '"data":"the message",' "$M" "should get newly submitted data" ) &
  sleep 1
  R=`$TEST -d $DEVICE_ID_1 $SECRET "$DATA"`
  assertEqual 1 $R "shoud have delivered directly"
  
  SECRET=`uuidgen`
}

function testNotReceivingOwnPastesWhenRequestingJson(){
  echo $FUNCNAME
  R=`$TEST -d $DEVICE_ID_2 $SECRET "from 2"`
  R=`$TEST -d $DEVICE_ID_1 $SECRET "from 1"`
  R=`$TEST -j -d $DEVICE_ID_2 $SECRET`
  D=`echo "$R" | grep -Po '"data":.*?[^\\\\]",'`
  assertEqual '"data":"from 1",' "$D" "should get recently stored data"
  assertContains "$DEVICE_ID_1" "$R" "should include id of sender"
  SECRET=`uuidgen`
}


function testFetchingOnlyUnknownRecentPastes(){
  echo $FUNCNAME
  R=`$TEST -d $DEVICE_ID_1 $SECRET "msg1"`
  R=`$TEST -d $DEVICE_ID_1 $SECRET "msg2"`
  R=`$TEST -d $DEVICE_ID_1 $SECRET "msg3"`
  R=`$TEST -j -d $DEVICE_ID_2 $SECRET`
  MSG2_ID=`echo "$R" | grep -Po '"data":"msg2","id":.*?[^\\\\]",' | awk -F"\"" '{print $8}'`
  R=`$TEST -j -d $DEVICE_ID_2 -s $MSG2_ID $SECRET`
  D=`echo "$R" | grep -Po '"data":.*?[^\\\\]",'`
  assertEqual '"data":"msg3",' "$D" "should get only the third message"
  MSG3_ID=`echo "$R" | awk -F"\"" '{print $8}'`
  ( M=`$TEST -j -d $DEVICE_ID_2 -s $MSG3_ID $SECRET | grep -Po '"data":.*?[^\\\\]",'`;   assertEqual '"data":"msg4",' "$M" "should get newly submitted data" ) &
  sleep 1  
  R=`$TEST -d $DEVICE_ID_1 $SECRET "msg4"`
  SECRET=`uuidgen`
}

function testDownloadingWhileUploading(){
  echo $FUNCNAME
  URI="http://localhost:8080/api/test/icon.jpg"
  curl -s -q -F "file=@../artwork/ios-icon-512.png" "$URI" --limit-rate 100k > /dev/null &
  sleep 2s
  wget -S $URI #&& rm icon.jpg
}

testSimpleTransfer
testFetchingRecentPaste
testFetchingTwoRecentPastes
testFetchingRecentPasteInJsonFormatWithDeviceId
testWaitingForPasteAsJsonWithDeviceId
testNotReceivingOwnPastesWhenRequestingJson
testFetchingOnlyUnknownRecentPastes
testDownloadingWhileUploading

wait && echo "SUCSESS"
