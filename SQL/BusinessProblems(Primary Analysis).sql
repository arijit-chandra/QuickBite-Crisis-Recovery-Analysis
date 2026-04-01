use QuickBite;
--Monthly Orders (Pre vs Crisis)
SELECT
    FORMAT(order_timestamp, 'yyyy-MM')  AS order_month,
    COUNT(*) AS total_orders,
    CASE 
        WHEN order_timestamp >= '2025-01-01' AND order_timestamp < '2025-06-01' THEN 'Pre-Crisis'
        WHEN order_timestamp >= '2025-06-01' AND order_timestamp < '2025-10-01' THEN 'Crisis'
    END AS period
FROM fact_orders
WHERE is_cancelled = 0
GROUP BY 
    FORMAT(order_timestamp, 'yyyy-MM'),
    CASE 
        WHEN order_timestamp >= '2025-01-01' AND order_timestamp < '2025-06-01' THEN 'Pre-Crisis'
        WHEN order_timestamp >= '2025-06-01' AND order_timestamp < '2025-10-01' THEN 'Crisis'
    END
ORDER BY order_month;

--Top 5 Cities with Highest % Decline
WITH city_orders AS (
    SELECT 
        dc.city,
        SUM(CASE 
                WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp < '2025-06-01' THEN 1 
                ELSE 0 
            END) AS pre_crisis_orders,  
        SUM(CASE 
                WHEN fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp < '2025-10-01' THEN 1 
                ELSE 0 
            END) AS crisis_orders
    FROM fact_orders fo
    JOIN dim_customer dc ON fo.customer_id = dc.customer_id
    WHERE fo.is_cancelled = 0
    GROUP BY dc.city
)
SELECT 
      TOP 5 *,
      ((pre_crisis_orders - crisis_orders) * 100.0 / NULLIF(pre_crisis_orders, 0)) AS decline_pct
FROM city_orders
ORDER BY decline_pct DESC;

--Top 10 High-Volume Restaurants Decline
WITH restaurant_order_volumes AS (
    SELECT
        fo.restaurant_id,
        dr.restaurant_name,
        dr.city,
        COUNT(CASE 
            WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp <  '2025-06-01' THEN 1 
        END) AS pre_crisis_orders,
        COUNT(CASE 
            WHEN fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp <  '2025-10-01' THEN 1 
        END) AS crisis_orders
    FROM fact_orders fo
    JOIN dim_restaurant dr ON fo.restaurant_id = dr.restaurant_id
    WHERE fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp <  '2025-10-01' AND fo.is_cancelled = 0
    GROUP BY fo.restaurant_id, dr.restaurant_name, dr.city
    HAVING COUNT(CASE 
        WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp <  '2025-06-01' THEN 1 
    END) > 0
),
top_pre_crisis_restaurants AS (
    SELECT
        rov.restaurant_id,
        rov.restaurant_name,
        rov.city,
        rov.pre_crisis_orders,
        rov.crisis_orders,
        ROW_NUMBER() OVER (ORDER BY rov.pre_crisis_orders DESC) AS pre_crisis_rank
    FROM restaurant_order_volumes rov
),
percentage_drops AS (
    SELECT
        tpr.restaurant_id,
        tpr.restaurant_name,
        tpr.city,
        tpr.pre_crisis_orders,
        tpr.crisis_orders,
        tpr.pre_crisis_rank,
        ROUND(
            (tpr.pre_crisis_orders - tpr.crisis_orders) * 100.0 / NULLIF(tpr.pre_crisis_orders, 0), 2
        ) AS percentage_drop,
        ROUND(
            tpr.crisis_orders * 100.0 / NULLIF(tpr.pre_crisis_orders, 0), 2
        ) AS crisis_vs_pre_crisis_pct
    FROM top_pre_crisis_restaurants tpr
    WHERE tpr.pre_crisis_rank <= 50
)
SELECT TOP 10
    pd.restaurant_id,
    pd.restaurant_name,
    pd.city,
    pd.pre_crisis_orders,
    pd.crisis_orders,
    pd.percentage_drop,
    pd.crisis_vs_pre_crisis_pct,
    pd.pre_crisis_rank
FROM percentage_drops pd
WHERE pd.percentage_drop > 0
ORDER BY pd.percentage_drop DESC;

--Cancellation Rate Trend
SELECT 
    dc.city,
    FORMAT(order_timestamp, 'yyyy-MM') AS order_month,
    COUNT(*) AS total_orders,
    SUM(CASE WHEN fo.is_cancelled = 1 THEN 1 ELSE 0 END) AS cancelled_orders,
    (SUM(CASE WHEN fo.is_cancelled = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*)) AS cancellation_rate
FROM fact_orders fo
JOIN dim_customer dc ON fo.customer_id = dc.customer_id
GROUP BY dc.city, FORMAT(order_timestamp, 'yyyy-MM')
ORDER BY dc.city, order_month;

-- City with Phase-wise
SELECT 
    dc.city,
    CASE 
        WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp < '2025-06-01' THEN 'Pre-Crisis'
        WHEN fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp < '2025-10-01' THEN 'Crisis'
    END AS period,
    COUNT(*) AS total_orders,
    SUM(CASE 
            WHEN fo.is_cancelled = 1 THEN 1 ELSE 0 
        END) AS cancelled_orders,
    (SUM(CASE 
            WHEN fo.is_cancelled = 1 THEN 1 ELSE 0 
         END) * 100.0 / COUNT(*)) AS cancellation_rate
FROM fact_orders fo
JOIN dim_customer dc ON fo.customer_id = dc.customer_id
WHERE fo.order_timestamp >= '2025-01-01'AND fo.order_timestamp < '2025-10-01'
GROUP BY dc.city,
    CASE 
        WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp < '2025-06-01' THEN 'Pre-Crisis'
        WHEN fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp < '2025-10-01' THEN 'Crisis'
    END
ORDER BY dc.city, period;


--Delivery SLA (Avg Delivery Time)
SELECT 
    CASE 
        WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp < '2025-06-01' THEN 'Pre-Crisis'
        WHEN fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp < '2025-10-01' THEN 'Crisis'
    END AS period,
    AVG(CAST(fdp.actual_delivery_time_mins AS FLOAT)) AS avg_delivery_time,
    AVG(CAST(fdp.expected_delivery_time_mins AS FLOAT)) AS avg_expected_time,
    AVG(
        CAST(fdp.actual_delivery_time_mins AS FLOAT) - 
        CAST(fdp.expected_delivery_time_mins AS FLOAT)
    ) AS avg_delay
FROM fact_orders fo
JOIN fact_delivery_performance fdp ON fo.order_id = fdp.order_id
WHERE fo.order_timestamp >= '2025-01-01'AND fo.order_timestamp < '2025-10-01'
GROUP BY 
    CASE 
        WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp < '2025-06-01' THEN 'Pre-Crisis'
        WHEN fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp < '2025-10-01' THEN 'Crisis'
    END;

--Ratings Fluctuation (Monthly)
SELECT 
    FORMAT(review_timestamp, 'yyyy-MM') AS review_month,
    AVG(rating) AS avg_rating
FROM fact_ratings
WHERE review_timestamp IS NOT NULL
GROUP BY FORMAT(review_timestamp, 'yyyy-MM')
ORDER BY review_month;

--Ratings Fluctuation (Tie to Crisis)
SELECT 
    CASE 
        WHEN review_timestamp >= '2025-01-01' AND review_timestamp < '2025-06-01' THEN 'Pre-Crisis'
        WHEN review_timestamp >= '2025-06-01' AND review_timestamp < '2025-10-01' THEN 'Crisis'
    END AS period,
    AVG(rating) AS avg_rating
FROM fact_ratings
WHERE review_timestamp IS NOT NULL
GROUP BY 
    CASE 
        WHEN review_timestamp >= '2025-01-01' AND review_timestamp < '2025-06-01' THEN 'Pre-Crisis'
        WHEN review_timestamp >= '2025-06-01' AND review_timestamp < '2025-10-01' THEN 'Crisis'
    END;

--Negative Keywords (For Word Cloud)
SELECT 
    value AS word,
    COUNT(*) AS frequency
FROM fact_ratings
CROSS APPLY STRING_SPLIT(LOWER(review_text), ' ')
WHERE review_timestamp >= '2025-06-01'AND review_timestamp < '2025-09-30'
  AND value NOT IN ('the','is','and','was','to','for','of','in','a')
GROUP BY value
ORDER BY frequency DESC;

--Revenue Impact
WITH base AS (
    SELECT *,
        CASE 
            WHEN order_timestamp >= '2025-01-01' AND order_timestamp < '2025-06-01' THEN 'Pre-Crisis'
            WHEN order_timestamp >= '2025-06-01' AND order_timestamp < '2025-10-01' THEN 'Crisis'
        END AS period
    FROM fact_orders
    WHERE is_cancelled = 0 AND order_timestamp >= '2025-01-01'AND order_timestamp < '2025-10-01'
)
SELECT
    period,
    SUM(subtotal_amount) AS total_subtotal,
    SUM(discount_amount) AS total_discount,
    SUM(delivery_fee) AS total_delivery_fee,
    SUM(total_amount) AS total_revenue
FROM base
GROUP BY period;

--Loyalty Impact (Churned Users)
WITH pre_crisis_customers AS (
    SELECT 
        fo.customer_id,
        COUNT(*) AS pre_crisis_orders
    FROM fact_orders fo
    WHERE fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp <= '2025-05-31' AND fo.is_cancelled = 0
    GROUP BY fo.customer_id
    HAVING COUNT(*) >= 5
),

crisis_activity AS (
    SELECT 
        fo.customer_id,
        COUNT(*) AS crisis_orders
    FROM fact_orders fo
    WHERE fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp <= '2025-09-30' AND fo.is_cancelled = 0
    GROUP BY fo.customer_id
),

customer_ratings AS (
    SELECT 
        fr.customer_id,
        AVG(CAST(fr.rating AS FLOAT)) AS avg_rating,
        COUNT(*) AS total_ratings
    FROM fact_ratings fr
    WHERE fr.rating IS NOT NULL
    GROUP BY fr.customer_id
),

analysis AS (
    SELECT 
        pc.customer_id,
        pc.pre_crisis_orders,
        ISNULL(ca.crisis_orders, 0) AS crisis_orders,
        cr.avg_rating,
        cr.total_ratings,
        CASE
            WHEN ISNULL(ca.crisis_orders, 0) = 0 THEN 'Stopped'
            ELSE 'Continued'
        END AS crisis_behavior
    FROM pre_crisis_customers pc
    LEFT JOIN crisis_activity ca ON pc.customer_id = ca.customer_id
    LEFT JOIN customer_ratings cr ON pc.customer_id = cr.customer_id
)

SELECT 
    crisis_behavior,
    COUNT(*) AS total_customers,
    COUNT(CASE 
            WHEN avg_rating > 4.5 THEN 1 
        END) AS customers_with_high_rating,
    ROUND(AVG(avg_rating), 2) AS average_rating_score
FROM analysis
GROUP BY crisis_behavior
ORDER BY crisis_behavior;


--High-Value Customers Decline (Top 5%)
WITH customer_spend AS (
    SELECT 
        customer_id,
        SUM(total_amount) AS total_spend
    FROM fact_orders
    WHERE order_timestamp >= '2025-01-01' AND order_timestamp < '2025-06-01'AND is_cancelled = 0
    GROUP BY customer_id
),
top_5_percent AS (
    SELECT customer_id
    FROM (
        SELECT 
            customer_id,
            total_spend,
            NTILE(20) OVER (ORDER BY total_spend DESC) AS percentile
        FROM customer_spend
    ) t
    WHERE percentile = 1
),
order_counts AS (
    SELECT 
        customer_id,
        COUNT_BIG(CASE 
            WHEN order_timestamp >= '2025-01-01' AND order_timestamp < '2025-06-01' THEN 1 
        END) AS pre_orders,
        COUNT_BIG(CASE 
            WHEN order_timestamp >= '2025-06-01' AND order_timestamp < '2025-10-01' THEN 1 
        END) AS crisis_orders
    FROM fact_orders
    WHERE is_cancelled = 0
    GROUP BY customer_id
),
ratings AS (
    SELECT 
        customer_id,
        AVG(CAST(
            CASE 
                WHEN review_timestamp >= '2025-01-01' AND review_timestamp < '2025-06-01' THEN rating 
            END AS FLOAT)) AS pre_rating,
        AVG(CAST(
            CASE 
                WHEN review_timestamp >= '2025-06-01' AND review_timestamp < '2025-10-01' THEN rating 
            END AS FLOAT)) AS crisis_rating
    FROM fact_ratings
    GROUP BY customer_id
),
delivery_delay AS (
    SELECT 
        fo.customer_id,
        AVG(
            CAST(fdp.actual_delivery_time_mins AS INT) - CAST(fdp.expected_delivery_time_mins AS INT)
        ) * 1.0 AS avg_delay
    FROM fact_delivery_performance fdp
    JOIN fact_orders fo ON fdp.order_id = fo.order_id
    GROUP BY fo.customer_id
),
customer_cuisine_base AS (
    SELECT 
        fo.customer_id,
        dr.cuisine_type,
        COUNT_BIG(*) AS order_count
    FROM fact_orders fo
    JOIN dim_restaurant dr ON fo.restaurant_id = dr.restaurant_id
    WHERE fo.is_cancelled = 0
    GROUP BY fo.customer_id, dr.cuisine_type
),
customer_cuisine AS (
    SELECT 
        customer_id,
        cuisine_type,
        order_count,
        ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_count DESC) AS rn
    FROM customer_cuisine_base
),
top_cuisine AS (
    SELECT 
        customer_id,
        cuisine_type
    FROM customer_cuisine
    WHERE rn = 1
),
combined AS (
    SELECT 
        t.customer_id,
        oc.pre_orders,
        oc.crisis_orders,
        CAST(oc.pre_orders AS INT) - CAST(oc.crisis_orders AS INT) AS order_drop,
        r.pre_rating
    FROM top_5_percent t
    LEFT JOIN order_counts oc ON t.customer_id = oc.customer_id
    LEFT JOIN ratings r ON t.customer_id = r.customer_id
)

SELECT TOP 10
    c.customer_id,
    dc.city,
    tc.cuisine_type AS top_cuisine,
    c.pre_orders,
    c.crisis_orders,
    c.order_drop,
    c.pre_rating,
    dd.avg_delay
FROM combined c
LEFT JOIN dim_customer dc ON c.customer_id = dc.customer_id
LEFT JOIN top_cuisine tc ON c.customer_id = tc.customer_id
LEFT JOIN delivery_delay dd ON c.customer_id = dd.customer_id
ORDER BY c.order_drop DESC;


--Priority Cities (Demand Loss)
SELECT 
    dc.city,
    SUM(CASE 
            WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp < '2025-06-01' THEN 1 
            ELSE 0 
        END) AS pre_crisis_orders,
    SUM(CASE 
            WHEN fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp < '2025-10-01' THEN 1 
            ELSE 0 
        END) AS crisis_orders,
    ((SUM(CASE 
            WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp < '2025-06-01' THEN 1 
            ELSE 0 
        END)
      -
      SUM(CASE 
            WHEN fo.order_timestamp >= '2025-06-01' AND fo.order_timestamp < '2025-10-01' THEN 1 
            ELSE 0 
        END)
     ) * 100.0 
     / NULLIF(SUM(CASE 
            WHEN fo.order_timestamp >= '2025-01-01' AND fo.order_timestamp < '2025-06-01' THEN 1 
        END), 0)
    ) AS decline_pct
FROM fact_orders fo
JOIN dim_customer dc ON fo.customer_id = dc.customer_id
WHERE fo.is_cancelled = 0
GROUP BY dc.city
ORDER BY decline_pct DESC;

--Feedback vs Delivery Delay
SELECT 
    FORMAT(fr.review_timestamp, 'yyyy-MM') AS month,
    AVG(fr.rating) AS avg_rating,
    AVG(fdp.actual_delivery_time_mins) AS avg_delivery_time
FROM fact_ratings fr
JOIN fact_delivery_performance fdp ON fr.order_id = fdp.order_id
GROUP BY FORMAT(fr.review_timestamp, 'yyyy-MM')
ORDER BY month;