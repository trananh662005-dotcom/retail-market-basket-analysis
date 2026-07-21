CREATE DATABASE Retail_MBA;
GO
USE Retail_MBA;
GO

-- 1. Tạo bảng Dim_Product với khóa tự sinh
SELECT 
    ROW_NUMBER() OVER (ORDER BY product_name) AS product_id,
    product_name,
    DENSE_RANK() OVER (ORDER BY category) AS category_id,
    category
INTO Dim_Product
FROM raw_sales_data
WHERE product_name IS NOT NULL
GROUP BY product_name, category;
GO
-- 2. Tạo bảng Dim_Customer chứa danh sách khách hàng duy nhất
SELECT DISTINCT 
    user_id
INTO Dim_Customer
FROM raw_sales_data
WHERE user_id IS NOT NULL;
GO
-- 3. Tạo bảng Fact_Sales 
SELECT 
    r.order_id,
    r.order_date,
    r.user_id,
    p.product_id,
    r.quantity,
    r.weighted_price,
    CAST(r.quantity * r.weighted_price AS DECIMAL(18, 2)) AS total_amount
INTO Fact_Sales
FROM raw_sales_data r
INNER JOIN Dim_Product p ON r.product_name = p.product_name AND r.category = p.category;
GO
-- ==========================================
-- THIẾT LẬP KHÓA CHÍNH (PRIMARY KEY)
-- ==========================================

-- 1. Khóa chính cho Dim_Product (product_id)
ALTER TABLE Dim_Product 
ALTER COLUMN product_id INT NOT NULL;

ALTER TABLE Dim_Product 
ADD CONSTRAINT PK_Dim_Product PRIMARY KEY (product_id);


-- 2. Khóa chính cho Dim_Customer (user_id)
ALTER TABLE Dim_Customer 
ALTER COLUMN user_id INT NOT NULL;

ALTER TABLE Dim_Customer 
ADD CONSTRAINT PK_Dim_Customer PRIMARY KEY (user_id);


-- ==========================================
-- THIẾT LẬP KHÓA NGOẠI (FOREIGN KEY)
-- ==========================================

-- 3. Liên kết Fact_Sales (product_id) -> Dim_Product (product_id)
ALTER TABLE Fact_Sales 
ALTER COLUMN product_id INT NOT NULL;

ALTER TABLE Fact_Sales 
ADD CONSTRAINT FK_Fact_Product FOREIGN KEY (product_id) 
REFERENCES Dim_Product (product_id);


-- 4. Liên kết Fact_Sales (user_id) -> Dim_Customer (user_id)
ALTER TABLE Fact_Sales 
ALTER COLUMN user_id INT NOT NULL;

ALTER TABLE Fact_Sales 
ADD CONSTRAINT FK_Fact_Customer FOREIGN KEY (user_id) 
REFERENCES Dim_Customer (user_id);
GO