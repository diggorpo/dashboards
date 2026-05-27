-- Сравнение текущих цен на товары (Минимум, Максимум, Средняя)
CREATE OR REPLACE VIEW view_product_price_summary AS
SELECT 
    product_id,
    COUNT(DISTINCT supplier_id) as suppliers_count,
    MIN(price) as min_price,
    MAX(price) as max_price,
    ROUND(AVG(price), 2) as avg_price,
    -- Рассчитываем спред (разницу между макс и мин ценой в процентах)
    ROUND(((MAX(price) - MIN(price)) / NULLIF(MIN(price), 0)) * 100, 2) as price_spread_pct
FROM view_latest_prices
GROUP BY product_id;
