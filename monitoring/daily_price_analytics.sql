-- показывает сводные данные по сегодняним ценам на товары (минимальную, медианную цены на товары)
WITH today_prices AS (
         SELECT price_history.product_id,
            price_history.supplier_id,
            price_history.price,
            price_history.flags,
            price_history.raw_text,
            price_history.created_at
           FROM monitor.price_history
          WHERE price_history.created_at >= CURRENT_DATE AND price_history.created_at < (CURRENT_DATE + '1 day'::interval)
        ), stats AS (
         SELECT today_prices.product_id,
            count(today_prices.supplier_id) AS supplier_count,
            avg(today_prices.price) AS avg_price,
            percentile_cont(0.5::double precision) WITHIN GROUP (ORDER BY (today_prices.price::double precision)) AS median_price,
            string_agg((((( SELECT suppliers.name
                   FROM suppliers
                  WHERE suppliers.id = today_prices.supplier_id))::text) || ': '::text) || today_prices.raw_text, chr(10)) AS all_supplier_texts
           FROM today_prices
          GROUP BY today_prices.product_id
        ), min_deals AS (
         SELECT DISTINCT ON (today_prices.product_id) today_prices.product_id,
            today_prices.price AS min_price,
            today_prices.supplier_id,
            today_prices.flags
           FROM today_prices
          ORDER BY today_prices.product_id, today_prices.price, today_prices.created_at DESC
        )
 SELECT p.id AS product_id,
    p.name AS product_name,
        CASE
            WHEN s.supplier_count < 3 THEN round(s.avg_price)::integer
            ELSE round(s.median_price)::integer
        END AS aggregated_price,
    m.min_price,
    sup.name AS min_price_supplier_name,
    m.flags AS min_price_flags,
    s.supplier_count AS total_suppliers_today,
    s.all_supplier_texts
   FROM stats s
     JOIN min_deals m ON s.product_id = m.product_id
     JOIN products p ON s.product_id = p.id
     JOIN suppliers sup ON m.supplier_id = sup.id;
