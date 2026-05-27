-- Актуальные (последние) цены по каждому товару и поставщику
CREATE OR REPLACE VIEW view_latest_prices AS
WITH ranked_prices AS (
    SELECT 
        id,
        product_id,
        supplier_id,
        price,
        flags,
        created_at,
        ROW_NUMBER() OVER (
            PARTITION BY product_id, supplier_id 
            ORDER BY created_at DESC
        ) as rn
    FROM monitor.price_history
)
SELECT 
    id,
    product_id,
    supplier_id,
    price,
    flags,
    created_at
FROM ranked_prices
WHERE rn = 1;
