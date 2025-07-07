CREATE USER 'db_create_user'@'$1' IDENTIFIED BY '$2';
GRANT ALL PRIVILEGES ON *.* TO 'db_create_user'@'$2';
