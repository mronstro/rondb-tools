DELIMITER $$

DROP DATABASE IF EXISTS benchmark;
CREATE DATABASE benchmark;
USE benchmark;
DROP PROCEDURE IF EXISTS generate_table_data$$
CREATE PROCEDURE generate_table_data(
    IN db_name VARCHAR(255),
    IN table_name VARCHAR(255),
    IN column_count INT,
    IN row_count INT,
    IN batch_size INT,
    IN column_info INT
)
BEGIN

    DECLARE i INT DEFAULT 0;
    DECLARE j INT DEFAULT 0;
    DECLARE loop_count INT DEFAULT 0;
    DECLARE col_name VARCHAR(255);
    DECLARE col_type VARCHAR(255);
    DECLARE create_db_sql TEXT;
    DECLARE create_table_sql TEXT;
    DECLARE insert_sql TEXT;
    DECLARE row_id INT DEFAULT 1;

    IF table_name IS NULL THEN SET table_name = 'benchmark_tbl'; END IF;
    IF column_count IS NULL THEN SET column_count = 10; END IF;
    IF row_count IS NULL THEN SET row_count = 100000; END IF;
    IF batch_size IS NULL THEN SET batch_size = 1000; END IF;

    SET create_table_sql = CONCAT('CREATE TABLE IF NOT EXISTS ', db_name, '.', table_name, ' (id0 INT PRIMARY KEY AUTO_INCREMENT, ');

    WHILE i < column_count DO
        SET col_name = CONCAT('c', i);
        IF column_info <= 0 THEN SET col_type = IF(MOD(i, 2) = 0, 'INT', 'VARCHAR(128)'); END IF;
        IF column_info = 1 THEN SET col_type = 'INT'; END IF;
        IF column_info = 2 THEN SET col_type = 'VARCHAR(128)'; END IF;
        IF column_info = 3 THEN SET col_type = 'VARCHAR(255)'; END IF;
        IF column_info = 4 THEN SET col_type = 'VARBINARY(2048)'; END IF;
        IF column_info = 5 THEN SET col_type = 'VARBINARY(29600)'; END IF;
        IF column_info = 6 THEN SET col_type = 'VARCHAR(2048)'; END IF;
        IF column_info >= 7 THEN SET col_type = 'VARBINARY(29600)'; END IF;
        SET create_table_sql = CONCAT(create_table_sql, col_name, ' ', col_type, ', ');
        SET i = i + 1;
    END WHILE;

		-- Remove last comma
    SET create_table_sql = LEFT(create_table_sql, LENGTH(create_table_sql) - 2);
    SET create_table_sql = CONCAT(create_table_sql, ') ENGINE=NDB CHARACTER SET latin1 COMMENT="NDB_TABLE=PARTITION_BALANCE=FOR_RP_BY_LDM_X_16";');

		-- Execute CREATE TABLE statement
    SET @stmt = create_table_sql;
    PREPARE stmt FROM @stmt;
    EXECUTE stmt;
    DEALLOCATE PREPARE stmt;

		-- Prepare INSERT statement structure
    SET insert_sql = CONCAT('INSERT INTO ', db_name, '.', table_name, ' (');
    SET i = 0;
    WHILE i < column_count DO
        SET insert_sql = CONCAT(insert_sql, 'c', i, ', ');
        SET i = i + 1;
    END WHILE;
		-- Remove last comma
    SET insert_sql = LEFT(insert_sql, LENGTH(insert_sql) - 2);
    SET insert_sql = CONCAT(insert_sql, ') VALUES ');

    -- Insert rows in batches
    SET @col_value = '';
    SET loop_count = 0;
    IF column_info = 3 THEN
        WHILE loop_count < 6 DO
            SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 36), '''');
            SET loop_count = loop_count + 1;
        END WHILE;
        SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 18), '''', ', ');
    END IF;
    IF column_info = 4 THEN
        WHILE loop_count < 52 DO
            SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 36), '''');
            SET loop_count = loop_count + 1;
        END WHILE;
        SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 20), '''', ', ');
    END IF;
    IF column_info = 5 THEN
        WHILE loop_count < 776 DO
            SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 36), '''');
            SET loop_count = loop_count + 1;
        END WHILE;
        SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 8), '''', ', ');
    END IF;
    IF column_info = 6 THEN
        WHILE loop_count < 52 DO
            SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 36), '''');
            SET loop_count = loop_count + 1;
        END WHILE;
        SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 8), '''', ', ');
    END IF;
    IF column_info >= 7 THEN
        WHILE loop_count < 776 DO
            SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 36), '''');
            SET loop_count = loop_count + 1;
        END WHILE;
        SET @col_value = CONCAT(@col_value, '''', LEFT(UUID(), 8), '''', ', ');
    END IF;
    WHILE row_id <= row_count DO
        SET @row_values = '';

        SET i = 0;
        WHILE i < batch_size AND row_id <= row_count DO
            SET @row_values = CONCAT(@row_values, '(');
            
            -- Add column values
            SET j = 0;
            WHILE j < column_count DO
                SET loop_count = 0;
                IF column_info <= 0 THEN
                    IF MOD(j, 2) = 0 THEN
                        SET @row_values = CONCAT(@row_values, FLOOR(RAND() * 1000), ', ');
                    ELSE
                        SET @row_values = CONCAT(@row_values, '''', LEFT(UUID(), 10), '''', ', ');
                    END IF;
                END IF;
                IF column_info = 1 THEN
                    SET @row_values = CONCAT(@row_values, FLOOR(RAND() * 1000), ', ');
                END IF;
                IF column_info = 2 THEN
                    SET @row_values = CONCAT(@row_values, '''', LEFT(UUID(), 10), '''', ', ');
                END IF;
                IF column_info >= 3 THEN
                    SET @row_values = CONCAT(@row_values, @col_value);
                END IF;
                SET j = j + 1;
            END WHILE;

            -- Remove last comma and close the row
            SET @row_values = LEFT(@row_values, LENGTH(@row_values) - 2);
            SET @row_values = CONCAT(@row_values, '), ');

            SET row_id = row_id + 1;
            SET i = i + 1;
        END WHILE;

        -- Remove last comma and add ';'
        SET @row_values = LEFT(@row_values, LENGTH(@row_values) - 2);
        SET @batch_insert_sql = CONCAT(insert_sql, @row_values, ';');

        SET @stmt = @batch_insert_sql;
        PREPARE stmt FROM @stmt;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END WHILE;
END$$

DELIMITER ;
