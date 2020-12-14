#!/bin/sh -l

mkfifo DIFFPIPE
sh -c "git diff ${BASE_COMMIT:-bbf5c9790} HEAD --numstat > DIFFPIPE &"

MOD_FILES=0
while read INS DEL FILE; do
	if [ $DEL -gt 0 ]; then
		sh -c "echo 기존 코드 변경이 감지되었습니다: $FILE"
		MOD_FILES=`expr $MOD_FILES + 1`
	fi
done < DIFFPIPE 
rm DIFFPIPE

if [ $MOD_FILES -gt 0 ]; then
	exit 1
else
	sh -c "echo 기존 코드의 로그가 모두 보존되어있습니다."
fi
