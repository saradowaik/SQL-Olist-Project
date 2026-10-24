-- =====================================================================
-- Olist E-Commerce Case Study (MySQL 8+)
-- =====================================================================
-- 1) MARGIN & COST
-- =====================================================================

-- A) Does Olist sell premium electronics?

-- A-i) Overview: Premium vs Standard within electronics
WITH electronics_items AS (
    SELECT
        oi.order_id,
        oi.product_id,
        oi.price,
        c.customer_state,
        CASE
            WHEN oi.price >= 1000 THEN 'Premium'
            ELSE 'Standard'
        END AS price_tier
    FROM order_items oi
    JOIN orders o
        ON oi.order_id = o.order_id
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN products p
        ON oi.product_id = p.product_id
    JOIN product_category_translation t
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
      AND t.product_category_name_english IN (
            'computers', 'computers_accessories', 'electronics',
            'telephony', 'fixed_telephony', 'tablets_printing_image',
            'audio', 'consoles_games', 'pc_gamer'
      )
)
SELECT
    price_tier,
    COUNT(*)                                              AS items_sold,
    COUNT(DISTINCT product_id)                            AS distinct_products,
    ROUND(SUM(price), 2)                                  AS revenue,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)      AS pct_of_items,
    ROUND(100 * SUM(price) / SUM(SUM(price)) OVER (), 2)  AS pct_of_revenue
FROM electronics_items
GROUP BY price_tier;

-- A-ii) Same split by customer state (where are premium electronics bought?)
WITH electronics_items AS (
    SELECT
        oi.price,
        c.customer_state,
        CASE
            WHEN oi.price >= 1000 THEN 'Premium'
            ELSE 'Standard'
        END AS price_tier
    FROM order_items oi
    JOIN orders o
        ON oi.order_id = o.order_id
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN products p
        ON oi.product_id = p.product_id
    JOIN product_category_translation t
        ON p.product_category_name = t.product_category_name
    WHERE o.order_status = 'delivered'
      AND t.product_category_name_english IN (
            'computers', 'computers_accessories', 'electronics',
            'telephony', 'fixed_telephony', 'tablets_printing_image',
            'audio', 'consoles_games', 'pc_gamer'
      )
)
SELECT
    customer_state,
    SUM(price_tier = 'Premium')   AS premium_items,
    SUM(price_tier = 'Standard')  AS standard_items,
    ROUND(100 * SUM(price_tier = 'Premium') / COUNT(*), 2) AS pct_premium
FROM electronics_items
GROUP BY customer_state
ORDER BY premium_items DESC;


-- B) Financial risk: lost revenue from canceled & unavailable orders

SELECT
    o.order_status,
    COUNT(DISTINCT o.order_id)                  AS total_orders,
    ROUND(SUM(oi.price), 2)                     AS lost_sales,
    ROUND(SUM(oi.freight_value), 2)             AS lost_freight,
    ROUND(SUM(oi.price + oi.freight_value), 2)  AS total_lost_opportunity
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status IN ('canceled', 'unavailable')
GROUP BY o.order_status
ORDER BY total_lost_opportunity DESC;


-- C) Financial risk: payment & installment exposure

SELECT
    payment_type,
    payment_installments,
    COUNT(DISTINCT order_id)      AS total_orders,
    ROUND(SUM(payment_value), 2)  AS total_value,
    ROUND(AVG(payment_value), 2)  AS avg_payment_value
FROM order_payments
WHERE payment_installments > 5
GROUP BY payment_type, payment_installments
ORDER BY payment_installments DESC, total_value DESC;


-- D) Revenue opportunities: high demand, few local sellers by state

WITH state_demand AS (
    SELECT
        c.customer_state                      AS state,
        COUNT(DISTINCT c.customer_unique_id)  AS total_buyers,
        ROUND(SUM(oi.price), 2)               AS total_state_demand
    FROM orders o
    JOIN customers c
        ON o.customer_id = c.customer_id
    JOIN order_items oi
        ON o.order_id = oi.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY c.customer_state
),
state_sellers AS (
    SELECT
        seller_state               AS state,
        COUNT(DISTINCT seller_id)  AS local_sellers
    FROM sellers
    GROUP BY seller_state
)
SELECT
    d.state,
    d.total_buyers,
    COALESCE(s.local_sellers, 0)                         AS local_sellers,
    d.total_state_demand,
    ROUND(d.total_buyers / NULLIF(s.local_sellers, 0), 1) AS buyers_per_seller
FROM state_demand d
LEFT JOIN state_sellers s
    ON d.state = s.state
ORDER BY d.total_state_demand DESC;


-- =====================================================================
-- 2) MARKET SIZE
-- =====================================================================

-- A) General market size (total value & orders, delivered only)
SELECT
    COUNT(DISTINCT o.order_id)                  AS total_orders,
    ROUND(SUM(oi.price), 2)                     AS item_sales_volume,
    ROUND(SUM(oi.freight_value), 2)             AS total_freight,
    ROUND(SUM(oi.price + oi.freight_value), 2)  AS total_market_size
FROM orders o
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered';


-- B) Market size by state (top 10 by item sales)
SELECT
    c.customer_state,
    COUNT(DISTINCT c.customer_unique_id)  AS total_customers,
    COUNT(DISTINCT o.order_id)            AS total_orders,
    ROUND(SUM(oi.price), 2)               AS state_market_size
FROM customers c
JOIN orders o
    ON o.customer_id = c.customer_id
JOIN order_items oi
    ON o.order_id = oi.order_id
WHERE o.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY state_market_size DESC
LIMIT 10;


-- C) Market size by product category (top 10)

SELECT
    COALESCE(t.product_category_name_english, 'unknown')  AS product_category,
    COUNT(DISTINCT o.order_id)                            AS total_orders,
    ROUND(SUM(oi.price), 2)                               AS total_market_size
FROM order_items oi
JOIN orders o
    ON oi.order_id = o.order_id
LEFT JOIN products p
    ON oi.product_id = p.product_id
LEFT JOIN product_category_translation t
    ON p.product_category_name = t.product_category_name
WHERE o.order_status = 'delivered'
GROUP BY product_category
ORDER BY total_market_size DESC
LIMIT 10;


-- =====================================================================
-- 3) DELIVERY & SATISFACTION
-- =====================================================================
-- Definition used throughout: 4-5 stars = Happy, 1-3 stars = Unhappy

-- A) Overall customer satisfaction
SELECT
    CASE
        WHEN r.review_score IN (4, 5) THEN 'Happy Customer'
        ELSE 'Unhappy Customer'
    END                                                  AS customer_satisfaction,
    COUNT(DISTINCT o.order_id)                           AS total_orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (), 2)     AS pct_of_reviews
FROM orders o
JOIN order_reviews r
    ON o.order_id = r.order_id
GROUP BY customer_satisfaction;


-- B) Customer satisfaction in São Paulo (SP)

SELECT
    c.customer_state,
    CASE
        WHEN r.review_score IN (4, 5) THEN 'Happy Customer'
        ELSE 'Unhappy Customer'
    END                                  AS customer_satisfaction,
    COUNT(DISTINCT o.order_id)           AS total_orders,
    ROUND(100 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY c.customer_state), 2)
                                         AS pct_within_state
FROM customers c
JOIN orders o
    ON c.customer_id = o.customer_id
JOIN order_reviews r
    ON o.order_id = r.order_id
WHERE c.customer_state = 'SP'
GROUP BY c.customer_state, customer_satisfaction;


-- C) Delivery status by price tier (Premium vs Standard)

SELECT
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN 'Not Delivered'
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Late'
        ELSE 'On Time'
    END                          AS delivery_status,
    CASE
        WHEN i.price >= 1000 THEN 'Premium'
        ELSE 'Standard'
    END                          AS price_tier,
    COUNT(DISTINCT o.order_id)   AS total_orders
FROM orders o
JOIN order_items i
    ON o.order_id = i.order_id
GROUP BY delivery_status, price_tier
ORDER BY price_tier, delivery_status;


-- D) Relation between delivery status and review score

SELECT
    CASE
        WHEN o.order_delivered_customer_date IS NULL THEN 'Not Delivered'
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Late'
        ELSE 'On Time'
    END                                       AS delivery_status,
    COUNT(DISTINCT o.order_id)                AS total_orders,
    ROUND(AVG(r.review_score), 2)             AS avg_review_score,
    ROUND(100 * AVG(r.review_score <= 3), 2)  AS pct_unhappy
FROM orders o
JOIN order_reviews r
    ON o.order_id = r.order_id
GROUP BY delivery_status
ORDER BY avg_review_score DESC;