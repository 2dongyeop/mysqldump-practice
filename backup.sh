#!/bin/bash

# MySQL 사용자 이름 및 비밀번호
USER="root"
PASSWORD="yourpassword"

# 백업 저장 경로
BACKUP_DIR="/path/to/backup/directory"

# 현재 날짜와 시간을 변수로 저장
TIMESTAMP=$(date +"%F_%T")

# 백업 파일 이름
DIAB_BACKUP_FILE="$BACKUP_DIR/$(date +%Y%m%d)-DiabDB.sql"

# 백업 명령 실행
mysqldump -u $USER -p DiabDB > $DIAB_BACKUP_FILE <<EOF
$PASSWORD
EOF

# 오래된(30일을 기준으로 함) 백업 파일 삭제
find $BACKUP_DIR -type f -name "*.sql" -mtime +30 -exec rm {} \;