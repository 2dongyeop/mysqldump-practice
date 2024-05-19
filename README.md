# mysqldump practive.
## 0. 목차
* [1. Overview](#1-overview)
* [2. AWS RDS의 백업 정책](#2-aws-rds의-백업-정책)
* [3. MySQL 백업 방식](#3-mysql-백업-방식)
    + [3-1. 백업 종류](#3-1-백업-종류)
    + [3-2. 백업 문법](#3-2-백업-문법)
    + [3-3. 백업 옵션](#3-3-백업-옵션)
    + [3-4. 예시 코드](#3-4-예시-코드)
    + [3-5. 바이너리로그를 이용한 PIT(Point to Time) 복구](#3-5-바이너리로그를-이용한-pitpoint-to-time-복구)
* [4. 실제 백업 해보기](#4-실제-백업-해보기)
    + [4-1. mysql을 실행하기 위한 `docker-compose.yml` 작성](#4-1-mysql을-실행하기-위한-docker-composeyml-작성)
    + [4-2. Docker에서 MySQL 실행](#4-2-docker에서-mysql-실행)
    + [4-3. mysqldump를 이용한 백업](#4-3-mysqldump를-이용한-백업)
    + [4-4. 백업본으로 복원하기](#4-4-백업본으로-복원하기)
* [5. 주기적으로 동작하도록 자동화하기](#5-주기적으로-동작하도록-자동화하기)
    + [5-1. `vi backup.sh` 작성](#5-1-vi-backupsh-작성)
    + [5-2. 크론 탭 등록](#5-2-크론-탭-등록)
    + [5-3. 크론 서비스 실행](#5-3-크론-서비스-실행)

## 1. Overview
Docker 컨테이너로 실행 중인 MySQL을 주기적으로 백업 실습 코드입니다.

자세한 내용은 [노션(첨부링크)](https://leedongyeop.notion.site/DB-MySQL-afa1eadacf6342b59403bdb42f53066e?pvs=4)에서 확인하실 수 있습니다.

<br/>

## 2. AWS RDS의 백업 정책
[AWS RDS Guide](https://docs.aws.amazon.com/ko_kr/prescriptive-guidance/latest/backup-recovery/rds.html)

1. 자동 백업 활성화시, 매일 자동으로 데이터에 대한 스냅샷을 생성 & 트랜잭션 로그를 캡쳐
    1. ex) snapshot-2024-05-10-1538 이라는 이름으로 생성.
2. 전체 DB 인스턴스 백업
3. 보존기간 내 언제든지 특정 시점으로 복구(PITR) 수행이 가능
    1. RDS 복원은 기존 RDS 인스턴스의 데이터가 복구되는 것이 아닐,
    복구 시점의 데이터를 바탕으로 새로운 RDS 인스턴스를 생성하는 것임.

<br/>

## 3. MySQL 백업 방식
### 3-1. 백업 종류

- mysqldump 명령어 이용
- mysqlhotcopy : 5.7버전에서부터는 제거
- xtrabackup : 별도 설치 필요

→ mysqldump 이용해보자.

<br/>

### 3-2. 백업 문법

```bash
$ mysqldump  [--옵션] --all-databases
$ mysqldump  [--옵션] --databases db_name
$ mysqldump  [--옵션] --databases db_name --tables table_name
```

<br/>

### 3-3. 백업 옵션

- **-all-database(-A)** : mysql와 모든 사용자 데이타베이스
- **-database(-B)** : 덤프할 데이타베이스 지정
- **-tables** : 데이타베이스에서 특정 테이블만 덤프
- **-single-transaction** : 데이타베이스 일관성 유지를 위해 mysqldump 실행전 서버에 START_TRANSACTION SQL 문을 보낸다.

<br/>

### 3-4. 예시 코드

```bash
# 전체 데이타 베이스 백업
mysqldump -u <username> -p<PASSWORD> -F --single-transaction --all-databases > alldatabase.sql

# 특정 데이타 베이스(testdb) 백업
mysqldump -u <username> -p<PASSWORD> -F --single-transaction --databases testdb > testdb.sql

# 특정 테이블(t1) 백업
mysqldump -u <username> -p<PASSWORD> --databases db_name --tables t1 > t1.sql

# 특정 테이블(t1)의 **구조만** 백업
mysqldump  -u <username> -p<PASSWORD> --no-data <데이터베이스명> > <백업파일명>.sql

# 데이타베이스 복구
mysql -u root -p PASSWORD < testdb.sql
```

<br/>

### 3-5. 바이너리로그를 이용한 PIT(Point to Time) 복구

덤프 백업 후 생성된 바이너리 로그 파일 확인 (ls -l 로 확인) 후에

덤프 후 생성된 바이너리 파일 2개 이상일 경우에 각각 바이너리 로그 파일마다 mysqlbinlog를 해줘야 한다.

```bash
# 현재 바이너리로그 파일 확인
mysql> show master status ;

+--------------------+----------+--------------+------------------+-------------------+
| File               | Position | Binlog_Do_DB | Binlog_Ignore_DB | Executed_Gtid_Set |
+--------------------+----------+--------------+------------------+-------------------+
| testsvr-bin.000031 |     7443 |              |                  |                   |
+--------------------+----------+--------------+------------------+-------------------+
1 row in set (0.00 sec)

# 장애 발생시
mysql> drop database testdb ;

# 바이너리 로그 파일 변환
shell> mysqlbinlog testsvr-bin.000031 > binlog.sql

# 데이터베이스 복구
shell> mysql -u root -pPASSWORD < testdb.sql

# 바이너리 로그 파일 복원
shell> mysql -u root -pPASSWORD < binlog.sql
```

<br/>

## 4. 실제 백업 해보기

### 4-1. mysql을 실행하기 위한 `docker-compose.yml` 작성
- docker가 설치되어 있지 않을 경우 [get-docker](https://get.docker.com/)를 이용하자.
```yaml
version: '3'
services:
  db:
    # image: mysql:8.0
    image: mysql:5.7
    container_name: mysql-container
    restart: always
    ports:
      - "3306:3306"
    environment:
      - MYSQL_ROOT_PASSWORD=dongyeop1204
      - TZ=Asia/Seoul
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
    volumes:
      - ./db/conf.d:/etc/mysql/conf.d
      - ./db/mysql/data:/var/lib/mysql
```

<br/>

### 4-2. Docker에서 MySQL 실행

- `sudo docker compose up -d`
- docker 명령어 permission denied 발생시
    - `sudo usermod -aG docker ${USER}`
    - `sudo chmod 666 /var/run/docker.sock`

<br/>

### 4-3. mysqldump를 이용한 백업
mysql-container 접속

```bash
$ docker exec -it mysql-container bash
```

mysqldump 명령어로 백업

```bash
# bash> mysqldump -u {username} -p {password} -F --single-transaction --all-databases > alldatabase.sql
bash> mysqldump -u root -p DiabDB > $(date +%Y%m%d)-DiabDB.sql
```

MySQL 접속 후 데이터 추가

```bash
# MySQL 접속
bash> mysql -u root -p

# INSERT data;
mysql> INSERT INTO admin (email, password) VALUES ('ldy_1204@naver.com2', 'example1234');
Query OK, 1 row affected (0.00 sec)
```

<br/>

### 4-4. 백업본으로 복원하기

다시 mysql-container의 bash에서 **복원** 진행

```bash
mysql> exit

bash> mysql -u root -p DiabDB < 20240519-DiabDB.sql
```

MySQL 접속 후 데이터가 복원되었는지 확인

```bash
# MySQL 접속
bash> mysql -u root -p

# 백업본은 데이터가 1개 있을 때 남겼으므로, 정상적으로 복원된것을 확인할 수 있음.
mysql> SELECT * FROM admin;
+----+--------------------+--------------+
| id | email              | password     |
+----+--------------------+--------------+
|  2 | ldy_1204@naver.com | example1234  |
+----+--------------------+--------------+
1 row in set (0.00 sec)
```

<br/>

## 5. 주기적으로 동작하도록 자동화하기

### 5-1. `vi backup.sh` 작성

백업 파일을 주기적으로 생성하고, 오래된(30일이 지난) 파일들을 지우는 스크립트 작성
```bash
#!/bin/bash

# MySQL 사용자 이름 및 비밀번호
USER="root"
PASSWORD="dongyeop1204"

# 백업 저장 경로
BACKUP_DIR="/backup"

# 백업 파일 이름
DIAB_BACKUP_FILE="$BACKUP_DIR/$(date +%Y%m%d)-DiabDB.sql"

# 백업 명령 실행
mysqldump -u $USER -p DiabDB > $DIAB_BACKUP_FILE <<EOF
$PASSWORD
EOF

# 오래된(30일을 기준으로 함) 백업 파일 삭제
find $BACKUP_DIR -type f -name "*.sql" -mtime +30 -exec rm {} \;
```

실행 권한 부여

```bash
$ chmod +x /backup.sh
```

<br/>

### 5-2. 크론 탭 등록
```bash
$ crontab -e

# 매주 일요일 새벽 2시에 백업 실행
# 아래 내용 추가
0 2 * * 0 /backup.sh
```

<br/>

### 5-3. 크론 서비스 실행

CentOS 기반

```bash
$ service crond start
```
