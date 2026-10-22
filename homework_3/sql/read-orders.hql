SET hive.fetch.task.conversion=more;
SET hive.fetch.task.conversion.threshold=10485760;
SELECT order_id, city, category, quantity, unit_price, status, dt
FROM dp_mashustova_hw3.orders;
