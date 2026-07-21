ALTER VIEW v_mba_pair_revenue AS
WITH ValidOrderIDs AS (
    SELECT order_id FROM Fact_Sales GROUP BY order_id HAVING COUNT(product_id) > 1
),
-- Tính doanh thu thực tế của từng sản phẩm riêng lẻ trong mỗi đơn hàng
ProductRevenuePerOrder AS (
    SELECT 
        s.order_id,
        p.product_id,
        p.product_name,
        p.category,
        s.total_amount
    FROM Fact_Sales s
    INNER JOIN Dim_Product p ON s.product_id = p.product_id
    WHERE s.order_id IN (SELECT order_id FROM ValidOrderIDs)
),
-- Tính tổng doanh thu của toàn bộ hệ thống siêu thị
GlobalCleanRevenue AS (
    SELECT
        SUM(total_amount) AS grand_total
    FROM Fact_Sales
),
-- Ghép cặp và cộng dồn doanh thu - CTE trung gian
PairAggregation AS (
    SELECT
        r1.product_id AS product_1id,
        r1.product_name AS Product1,
        r1.category AS Category1,
        r2.product_id AS product_2id,
        r2.product_name AS Product2,
        r2.category AS Category2, 
        CASE 
            WHEN r1.category = r2.category THEN 'Within-Category'
            ELSE 'Cross-Category'
        END AS Link_Type,
        COUNT(DISTINCT r1.order_id) AS TransactionCount,
        SUM(r1.total_amount + r2.total_amount) AS TotalRevenue,
        ROUND((SUM(r1.total_amount + r2.total_amount) / (SELECT grand_total FROM GlobalCleanRevenue)) * 100, 2) AS PercentTotalRevenue,
        -- Tính tổng line_total riêng cho từng sản phẩm trong các order chứa cặp
        SUM(r1.total_amount) AS Product1_TotalRevenue,
        SUM(r2.total_amount) AS Product2_TotalRevenue   
    FROM ProductRevenuePerOrder r1
    INNER JOIN ProductRevenuePerOrder r2 ON r1.order_id = r2.order_id AND r1.product_id < r2.product_id
    GROUP BY r1.product_id, r2.product_id, r1.product_name, r2.product_name, r1.category, r2.category
)
SELECT
    product_1id,
    Product1,
    Category1,
    product_2id,
    Product2,
    Category2,
    Link_Type,
    TransactionCount,
    TotalRevenue,
    PercentTotalRevenue,
    CASE 
        WHEN Product1_TotalRevenue >= Product2_TotalRevenue 
        THEN Product1 + ' - ' + Product2
        ELSE Product2 + ' - ' + Product1
    END AS PairName
FROM PairAggregation;
GO
-- Phân tích hành vi khách hàng dựa trên mua hàng kèm
ALTER VIEW v_customer_mba_behavior AS
WITH OrderSummary AS
(
    SELECT
        s.order_id,
        s.user_id,
        s.order_date,
        COUNT(s.product_id) AS ItemsInBasket,
        SUM(s.total_amount) AS OrderTotal
    FROM Fact_Sales s
    GROUP BY s.order_id, s.user_id, s.order_date
),
CustomerBehaviorStats AS
(
    SELECT
        c.user_id,
        COUNT(DISTINCT os.order_id) AS OrderCount,
        SUM(os.OrderTotal) AS TotalSpend,
        AVG(os.OrderTotal) AS AvgOrderValue,
        AVG(CAST(os.ItemsInBasket AS FLOAT)) AS AvgBasketSize,
        MIN(os.order_date) AS FirstOrderDate,
        MAX(os.order_date) AS LastOrderDate
    FROM Dim_Customer c
    LEFT JOIN OrderSummary os ON c.user_id = os.user_id
    GROUP BY c.user_id
),
CustomerRanking AS
(
    SELECT
        user_id,
        OrderCount,
        TotalSpend,
        AvgOrderValue,
        AvgBasketSize,
        FirstOrderDate,
        LastOrderDate,
        NTILE(4) OVER (ORDER BY TotalSpend DESC)     AS SpendScore,
        NTILE(4) OVER (ORDER BY AvgBasketSize DESC)  AS BasketScore
    FROM CustomerBehaviorStats
)
SELECT
    user_id,
    OrderCount,
    ROUND(TotalSpend,2) AS TotalSpend,
    ROUND(AvgOrderValue,2) AS AvgOrderValue,
    ROUND(AvgBasketSize,2) AS AvgBasketSize,
    FirstOrderDate,
    LastOrderDate,
    CASE
        WHEN SpendScore = 1
         AND BasketScore = 1
            THEN 'Premium Buyer'
        WHEN SpendScore <= 2
         AND BasketScore <= 2
            THEN 'Regular Buyer'
        WHEN SpendScore <= 3
            THEN 'Occasional Buyer'
        ELSE 'Low Value Buyer'
    END AS CustomerSegment
FROM CustomerRanking
WHERE OrderCount > 0;