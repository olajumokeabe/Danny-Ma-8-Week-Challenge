USE data_bank

--1. How many unique nodes are there on the Data Bank system?

SELECT COUNT(DISTINCT node_id) AS unique_nodes
FROM customer_nodes;


--2. What is the number of nodes per region?

SELECT 
  r.region_id,
  r.region_name,
  COUNT(n.node_id) AS nodes
FROM customer_nodes n
JOIN regions r
  ON n.region_id = r.region_id
GROUP BY r.region_id, r.region_name
ORDER BY r.region_id;


--3. How many customers are allocated to each region?

SELECT 
  r.region_id,
  r.region_name,
  COUNT(DISTINCT n.customer_id) AS customers
FROM customer_nodes n
JOIN regions r
  ON n.region_id = r.region_id
GROUP BY r.region_id, r.region_name
ORDER BY r.region_id;


--4. How many days on average are customers reallocated to a different node?

WITH customerDates AS (
  SELECT 
    customer_id,
    region_id,
    node_id,
    MIN(start_date) AS first_date
  FROM customer_nodes
  GROUP BY customer_id, region_id, node_id
),
reallocation AS (
  SELECT
    customer_id,
    node_id,
    region_id,
    first_date,
    DATEDIFF(DAY, first_date, 
             LEAD(first_date) OVER(PARTITION BY customer_id 
                                   ORDER BY first_date)) AS moving_days
  FROM customerDates
)

SELECT 
  AVG(CAST(moving_days AS FLOAT)) AS avg_moving_days
FROM reallocation;


--5. What is the median, 80th and 95th percentile for this same reallocation days metric for each region?

WITH customerDates AS (
  SELECT 
    customer_id,
    region_id,
    node_id,
    MIN(start_date) AS first_date
  FROM customer_nodes
  GROUP BY customer_id, region_id, node_id
),
reallocation AS (
  SELECT
    customer_id,
    region_id,
    node_id,
    first_date,
    DATEDIFF(DAY, first_date, LEAD(first_date) OVER(PARTITION BY customer_id ORDER BY first_date)) AS moving_days
  FROM customerDates
)

SELECT 
  DISTINCT r.region_id,
  rg.region_name,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY r.moving_days) OVER(PARTITION BY r.region_id) AS median,
  PERCENTILE_CONT(0.8) WITHIN GROUP (ORDER BY r.moving_days) OVER(PARTITION BY r.region_id) AS percentile_80,
  PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY r.moving_days) OVER(PARTITION BY r.region_id) AS percentile_95
FROM reallocation r
JOIN regions rg ON r.region_id = rg.region_id
WHERE moving_days IS NOT NULL;



--B. Customer Transactions--


--1. What is the unique count and total amount for each transaction type?

SELECT 
  txn_type,
  COUNT(*) AS unique_count,
  SUM(txn_amount) AS total_amount
FROM customer_transactions
GROUP BY txn_type;


--2. What is the average total historical deposit counts and amounts for all customers?

WITH customerDeposit AS (
  SELECT 
    customer_id,
    txn_type,
    COUNT(*) AS dep_count,
    SUM(txn_amount) AS dep_amount
  FROM customer_transactions
  WHERE txn_type = 'deposit'
  GROUP BY customer_id, txn_type
)

SELECT
  AVG(dep_count) AS avg_dep_count,
  AVG(dep_amount) AS avg_dep_amount
FROM customerDeposit;


--3. For each month - how many Data Bank customers make more than 1 deposit and either 1 purchase or 1 withdrawal in a single month?

WITH cte_transaction AS (
  SELECT 
    customer_id,
    MONTH(txn_date) AS months,
    SUM(CASE WHEN txn_type = 'deposit' THEN 1 ELSE 0 END) AS deposit_count,
    SUM(CASE WHEN txn_type = 'purchase' THEN 1 ELSE 0 END) AS purchase_count,
    SUM(CASE WHEN txn_type = 'withdrawal' THEN 1 ELSE 0 END) AS withdrawal_count
  FROM customer_transactions
  GROUP BY customer_id, MONTH(txn_date)
)

SELECT 
  months,
  COUNT(customer_id) AS customer_count
FROM cte_transaction
WHERE deposit_count > 1
  AND (purchase_count = 1 OR withdrawal_count = 1)
GROUP BY months;


--4. What is the closing balance for each customer at the end of the month?

--End date in the month of the max date of our dataset
DECLARE @maxDate DATE = (SELECT EOMONTH(MAX(txn_date)) FROM customer_transactions)

--CTE 1: Monthly transactions of each customer
WITH monthly_transactions AS (
  SELECT
    customer_id,
    EOMONTH(txn_date) AS end_date,
    SUM(CASE WHEN txn_type IN ('withdrawal', 'purchase') THEN -txn_amount
             ELSE txn_amount END) AS transactions
  FROM customer_transactions
  GROUP BY customer_id, EOMONTH(txn_date)
),

--CTE 2: Increment last days of each month till they are equal to @maxDate 
recursive_dates AS (
  SELECT
    DISTINCT customer_id,
    CAST('2020-01-31' AS DATE) AS end_date
  FROM customer_transactions
  UNION ALL
  SELECT 
    customer_id,
    EOMONTH(DATEADD(MONTH, 1, end_date)) AS end_date
  FROM recursive_dates
  WHERE EOMONTH(DATEADD(MONTH, 1, end_date)) <= @maxDate
)

SELECT 
  r.customer_id,
  r.end_date,
  COALESCE(m.transactions, 0) AS transactions,
  SUM(m.transactions) OVER (PARTITION BY r.customer_id ORDER BY r.end_date 
      ROWS UNBOUNDED PRECEDING) AS closing_balance
FROM recursive_dates r
LEFT JOIN  monthly_transactions m
  ON r.customer_id = m.customer_id
  AND r.end_date = m.end_date;


--5. What is the percentage of customers who increase their closing balance by more than 5%?

--End date in the month of the max date of our dataset (Q4)
DECLARE @maxDate DATE = (SELECT EOMONTH(MAX(txn_date)) FROM customer_transactions)

--CTE 1: Monthly transactions of each customer (Q4)
WITH monthly_transactions AS (
  SELECT
    customer_id,
    EOMONTH(txn_date) AS end_date,
    SUM(CASE WHEN txn_type IN ('withdrawal', 'purchase') THEN -txn_amount
             ELSE txn_amount END) AS transactions
  FROM customer_transactions
  GROUP BY customer_id, EOMONTH(txn_date)
),

--CTE 2: Increment last days of each month till they are equal to @maxDate (Q4)
recursive_dates AS (
  SELECT
    DISTINCT customer_id,
    CAST('2020-01-31' AS DATE) AS end_date
  FROM customer_transactions
  UNION ALL
  SELECT 
    customer_id,
    EOMONTH(DATEADD(MONTH, 1, end_date)) AS end_date
  FROM recursive_dates
  WHERE EOMONTH(DATEADD(MONTH, 1, end_date)) <= @maxDate
),

-- CTE 3: Closing balance of each customer by monthly (Q4)
customers_balance AS (
  SELECT 
    r.customer_id,
    r.end_date,
    COALESCE(m.transactions, 0) AS transactions,
    SUM(m.transactions) OVER (PARTITION BY r.customer_id ORDER BY r.end_date 
        ROWS UNBOUNDED PRECEDING) AS closing_balance
    FROM recursive_dates r
    LEFT JOIN  monthly_transactions m
      ON r.customer_id = m.customer_id
      AND r.end_date = m.end_date
),

--CTE 4: CTE 3 & next_balance
customers_next_balance AS (
  SELECT *,
    LEAD(closing_balance) OVER(PARTITION BY customer_id ORDER BY end_date) AS next_balance
  FROM customers_balance
),

--CTE 5: Calculate the increase percentage of closing balance for each customer
pct_increase AS (
  SELECT *,
    100.0*(next_balance-closing_balance)/closing_balance AS pct
  FROM customers_next_balance
  WHERE closing_balance ! = 0 AND next_balance IS NOT NULL
)

--Create a temporary table because of the error: Null value is eliminated by an aggregate or other SET operation
SELECT *
INTO #temp
FROM pct_increase;

--Calculate the percentage of customers whose closing balance increasing 5% compared to the previous month
SELECT CAST(100.0*COUNT(DISTINCT customer_id) AS FLOAT)
      / (SELECT COUNT(DISTINCT customer_id) FROM customer_transactions) AS pct_customers
FROM #temp
WHERE pct > 5;