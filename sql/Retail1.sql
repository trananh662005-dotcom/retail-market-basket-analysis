ALTER VIEW v_market_basket_metrics AS
WITH
-- BƯỚC 1
ValidOrderIDs AS (
    SELECT order_id
    FROM Fact_Sales
    GROUP BY order_id
    HAVING COUNT(product_id) > 1
),
-- BƯỚC 2
TotalValidOrders AS (
    SELECT COUNT(*) AS total_orders
    FROM ValidOrderIDs
),
-- BƯỚC 3
ValidOrderDetails AS (
    SELECT
        s.order_id,
        s.product_id,
        p.product_name,
        p.category_id,
        p.category
    FROM Fact_Sales s
    INNER JOIN Dim_Product p ON s.product_id = p.product_id
    WHERE s.order_id IN (SELECT order_id FROM ValidOrderIDs)
),
-- BƯỚC 4
ProductFrequency AS (
    SELECT
        product_id,
        COUNT(DISTINCT order_id) AS single_count,
        CAST(COUNT(DISTINCT order_id) AS FLOAT)
            / (SELECT total_orders FROM TotalValidOrders) AS single_support
    FROM ValidOrderDetails
    GROUP BY product_id
),
-- BƯỚC 5
ProductPairs AS (
    SELECT
        od1.product_id AS product_1id,
        od1.product_name AS product_1name,
        od1.category AS product_1category,
        od2.product_id AS product_2id,
        od2.product_name AS product_2name,
        od2.category AS product_2category,
        COUNT(DISTINCT od1.order_id) AS pair_count
    FROM ValidOrderDetails od1
     INNER JOIN ValidOrderDetails od2
        ON od1.order_id = od2.order_id
       AND od1.product_id < od2.product_id
    GROUP BY
        od1.product_id,
        od1.product_name,
        od1.category,
        od2.product_id,
        od2.product_name,
        od2.category
),
-- BƯỚC 6: Tính toàn bộ chỉ số MBA
MBA_Metrics AS (
SELECT
    p.product_1id,
    p.product_1name,
    p.product_1category,
    p.product_2id,
    p.product_2name,
    p.product_2category,
    p.pair_count,
    CASE
        WHEN p.product_1category = p.product_2category
            THEN 'Within Category'
        ELSE 'Cross Category'
    END AS Link_Type,
    ROUND(
        CAST(p.pair_count AS FLOAT)
        /(SELECT total_orders FROM TotalValidOrders)
    ,4) AS support,
    ROUND(
        CAST(p.pair_count AS FLOAT)
        /f1.single_count
    ,4) AS confidence_1_to_2,
    ROUND(
        CAST(p.pair_count AS FLOAT)
        /f2.single_count
    ,4) AS confidence_2_to_1,
    ROUND(
        (CAST(p.pair_count AS FLOAT)/f1.single_count)
        /f2.single_support
    ,4) AS lift,
    ROUND(
        (CAST(p.pair_count AS FLOAT)
        /(SELECT total_orders FROM TotalValidOrders))
        -
        (f1.single_support*f2.single_support)
    ,4) AS leverage,
    CASE
        WHEN ROUND(
            CAST(p.pair_count AS FLOAT)/f1.single_count
        ,4)=1
            THEN -999.0000

        ELSE ROUND(
            (1-f2.single_support)
            /
            (1-(CAST(p.pair_count AS FLOAT)/f1.single_count))
        ,4)
    END AS conviction_1_to_2
FROM ProductPairs p
INNER JOIN ProductFrequency f1
    ON p.product_1id = f1.product_id
INNER JOIN ProductFrequency f2
    ON p.product_2id = f2.product_id
)
-- BƯỚC 7: Thêm MaxConfidence và StrongDirection
SELECT
    product_1id,
    product_1name,
    product_1category,
    product_2id,
    product_2name,
    product_2category,
    pair_count,
    Link_Type,
    support,
    confidence_1_to_2,
    confidence_2_to_1,
    lift,
    leverage,
    conviction_1_to_2,
    CASE
        WHEN confidence_1_to_2 >= confidence_2_to_1
            THEN confidence_1_to_2
        ELSE confidence_2_to_1
    END AS MaxConfidence,
    CASE
        WHEN confidence_1_to_2 >= confidence_2_to_1
            THEN CONCAT(product_1name,' - ',product_2name)
        ELSE CONCAT(product_2name,' - ',product_1name)
    END AS StrongDirection
FROM MBA_Metrics;