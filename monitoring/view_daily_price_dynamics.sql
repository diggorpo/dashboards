--  Агрегированная динамика цен по дням (для линейного графика)
CREATE OR REPLACE VIEW view_daily_price_dynamics AS
SELECT 
    DATE(created_at) as price_date,
    product_id,
    supplier_id,
    ROUND(AVG(price), 2) as avg_daily_price
FROM monitor.price_history
GROUP BY DATE(created_at), product_id, supplier_id;
