 WITH order_sku_counts AS (
         SELECT order_finance.order_id,
            count(*) AS sku_count
           FROM yandex.order_finance
          GROUP BY order_finance.order_id
        ), ranked_transactions AS (
         SELECT DISTINCT ON (ot.id) ot.order_id,
            ot.shop_sku,
            ot.transaction_sum,
            conf.target_column,
            conf.financial_group
           FROM yandex.order_transactions ot
             JOIN yandex.finance_config conf ON TRIM(BOTH FROM lower(ot.transaction_source::text)) = TRIM(BOTH FROM lower(conf.yandex_source::text)) AND (conf.yandex_service IS NULL OR TRIM(BOTH FROM lower(ot.offer_or_service_name::text)) = TRIM(BOTH FROM lower(conf.yandex_service::text)))
          ORDER BY ot.id, (
                CASE
                    WHEN conf.yandex_service IS NOT NULL THEN 1
                    ELSE 2
                END)
        ), transaction_aggregates AS (
         SELECT ranked_transactions.order_id,
            ranked_transactions.shop_sku,
            sum(ranked_transactions.transaction_sum) FILTER (WHERE ranked_transactions.target_column::text = 'tl_paid_rub'::text) AS inc_paid_rub,
            sum(ranked_transactions.transaction_sum) FILTER (WHERE ranked_transactions.target_column::text = 'tl_pending_amount'::text) AS inc_pending,
            sum(ranked_transactions.transaction_sum) FILTER (WHERE ranked_transactions.target_column::text = 'tl_compensation'::text) AS inc_compensation,
            sum(ranked_transactions.transaction_sum) FILTER (WHERE ranked_transactions.financial_group::text = 'INFO'::text AND ranked_transactions.transaction_sum > 0::numeric) AS inc_points,
            sum(ranked_transactions.transaction_sum) AS total_yandex_net_flow
           FROM ranked_transactions
          GROUP BY ranked_transactions.order_id, ranked_transactions.shop_sku
        ), final_metrics AS (
         SELECT f_1.id AS finance_record_id,
            COALESCE(ta_s.inc_paid_rub, 0::numeric) + COALESCE(ta_o.inc_paid_rub / NULLIF(osc.sku_count, 0)::numeric, 0::numeric) + COALESCE(ta_s.inc_pending, 0::numeric) + COALESCE(ta_o.inc_pending / NULLIF(osc.sku_count, 0)::numeric, 0::numeric) + COALESCE(ta_s.inc_compensation, 0::numeric) + COALESCE(ta_o.inc_compensation / NULLIF(osc.sku_count, 0)::numeric, 0::numeric) + COALESCE(ta_s.inc_points, 0::numeric) + COALESCE(ta_o.inc_points / NULLIF(osc.sku_count, 0)::numeric, 0::numeric) AS total_income_fact,
            COALESCE(ta_s.total_yandex_net_flow, 0::numeric) + COALESCE(ta_o.total_yandex_net_flow / NULLIF(osc.sku_count, 0)::numeric, 0::numeric) AS net_payout_fact,
            COALESCE(f_1.est_placement_fee, 0::numeric) + COALESCE(f_1.est_boost_fee, 0::numeric) + COALESCE(f_1.est_delivery_customer, 0::numeric) + COALESCE(f_1.est_express_delivery, 0::numeric) + COALESCE(f_1.est_avg_mile, 0::numeric) + COALESCE(f_1.est_regional_delivery, 0::numeric) + COALESCE(f_1.est_payment_acceptance, 0::numeric) + COALESCE(f_1.est_payment_transfer, 0::numeric) + COALESCE(f_1.est_order_processing, 0::numeric) AS total_est_yandex_fees
           FROM yandex.order_finance f_1
             LEFT JOIN order_sku_counts osc ON f_1.order_id::text = osc.order_id::text
             LEFT JOIN transaction_aggregates ta_s ON f_1.order_id::text = ta_s.order_id::text AND TRIM(BOTH FROM lower(f_1.sku::text)) = TRIM(BOTH FROM lower(ta_s.shop_sku::text))
             LEFT JOIN transaction_aggregates ta_o ON f_1.order_id::text = ta_o.order_id::text AND ta_o.shop_sku IS NULL
        )
 SELECT f.order_id AS "ID заказа",
    f.sku AS "SKU",
    c.yandex_campaign_id AS "ID кампании",
    f.yandex_status AS "Статус",
    f.selling_price AS "Цена продажи",
    round(m.total_income_fact, 2) AS "Валовый доход (Total Income)",
    round(m.net_payout_fact, 2) AS "К выплате от Яндекса (Payout)",
    round(m.net_payout_fact -
        CASE
            WHEN lower(f.yandex_status::text) = 'delivered'::text OR m.total_income_fact >= (f.selling_price * 0.8) THEN f.purchase_price + COALESCE(f.estimated_tax, 0::numeric) + COALESCE(f.courier_delivery_cost, 0::numeric)
            ELSE COALESCE(f.courier_delivery_cost, 0::numeric)
        END, 2) AS "Чистая прибыль",
        CASE
            WHEN f.selling_price > 0::numeric THEN round((m.net_payout_fact -
            CASE
                WHEN lower(f.yandex_status::text) = 'delivered'::text THEN f.purchase_price + COALESCE(f.estimated_tax, 0::numeric) + COALESCE(f.courier_delivery_cost, 0::numeric)
                ELSE COALESCE(f.courier_delivery_cost, 0::numeric)
            END) / f.selling_price, 4)
            ELSE 0::numeric
        END AS "Маржа"
   FROM yandex.order_finance f
     JOIN yandex.campaigns c ON f.campaign_id = c.id
     JOIN final_metrics m ON f.id = m.finance_record_id
  ORDER BY f.order_date DESC;
