use pizza_runner
                 /*PIZZA METRICS
Data cleaning
Create a temporary table #customer_orders_temp from customer_orders table:
Convert null values and 'null' text values in exclusions and extras into blank ''.*/

SELECT 
  order_id,
  customer_id,
  pizza_id,
  CASE 
  	WHEN exclusions IS NULL OR exclusions LIKE 'null' THEN ''
    	ELSE exclusions 
    	END AS exclusions,
  CASE 
  	WHEN extras IS NULL OR extras LIKE 'null' THEN ''
    	ELSE extras 
    	END AS extras,
  order_time
INTO #customer_orders_temp
FROM customer_orders;

SELECT *
FROM #customer_orders_temp;


/*Create a temporary table #runner_orders_temp from runner_orders table:
Convert 'null' text values in pickup_time, duration and cancellation into null values.
Cast pickup_time to DATETIME.
Cast distance to FLOAT.
Cast duration to INT.*/

SELECT 
  order_id,
  runner_id,
  CAST(
  	CASE WHEN pickup_time LIKE 'null' THEN NULL ELSE pickup_time END 
      AS DATETIME) AS pickup_time,
  CAST(
  	CASE WHEN distance LIKE 'null' THEN NULL
        WHEN distance LIKE '%km' THEN TRIM('km' FROM distance)
        ELSE distance END
    AS FLOAT) AS distance,
  CAST(
  	CASE WHEN duration LIKE 'null' THEN NULL
        WHEN duration LIKE '%mins' THEN TRIM('mins' FROM duration)
        WHEN duration LIKE '%minute' THEN TRIM('minute' FROM duration)
        WHEN duration LIKE '%minutes' THEN TRIM('minutes' FROM duration)
        ELSE duration END
    AS INT) AS duration,
  CASE WHEN cancellation IN ('null', 'NaN', '') THEN NULL 
      ELSE cancellation
      END AS cancellation
INTO #runner_orders_temp
FROM runner_orders;

SELECT *
FROM #runner_orders_temp;

-- How many pizzas were ordered?
SELECT COUNT(order_id) AS pizza_count
FROM #customer_orders_temp;

--How many unique customers were made
SELECT COUNT(DISTINCT customer_id) AS customer_count
FROM #customer_orders_temp

--How many pizzas were ordered?
SELECT COUNT(DISTINCT order_id) AS order_count
FROM #customer_orders_temp;

--How many successful orders were delivered by each runner?
SELECT 
  runner_id,
  COUNT(order_id) AS successful_orders
FROM #runner_orders_temp
WHERE cancellation IS NULL
GROUP BY runner_id;

 --How many Vegetarian and Meatlovers were ordered by each customer?
SELECT 
  customer_id,
  SUM(CASE WHEN pizza_id = 1 THEN 1 ELSE 0 END) AS Meatlovers,
  SUM(CASE WHEN pizza_id = 2 THEN 1 ELSE 0 END) AS Vegetarian
FROM #customer_orders_temp
GROUP BY customer_id;


--What was the maximum number of pizzas delivered in a single order?
SELECT TOP 1
    COUNT(order_id) AS max_single_order
FROM
    #customer_orders_temp
GROUP BY customer_id , order_id
ORDER BY COUNT(order_id) DESC;

--For each customer, how many delivered pizzas had at least 1 change and how many had no changes?
SELECT 
    customer_id,
    SUM(CASE
        WHEN
            (exclusions IS NOT NULL
                OR extras IS NOT NULL) THEN 1
		ELSE 0
    END) AS with_changes,
    SUM(CASE WHEN (exclusions IS NULL AND extras IS NULL) THEN 1
        ELSE 0
    END) AS without_changes
FROM
    #customer_orders_temp c
        JOIN
    #runner_orders_temp r ON c.order_id = r.order_id
GROUP BY customer_id;

--How many pizzas were delivered that had both exclusions and extras?
SELECT 
  SUM(CASE WHEN exclusions != '' AND extras != '' THEN 1 ELSE 0 END) AS 'with exclusion and extra'
FROM #customer_orders_temp c
JOIN #runner_orders_temp r 
  ON c.order_id = r.order_id
WHERE r.cancellation IS NULL;

--What was the total volume of pizzas ordered for each hour of the day?
SELECT 
    DATEPART(hh, order_time) AS hour,
    COUNT(order_id) AS pizza_ordered
FROM
    #customer_orders_temp
GROUP BY DATEPART(hh,order_time)
ORDER BY DATEPART(hh,order_time);

--What was the volume of orders for each day of the week?
SELECT 
	DATENAME(DW, order_time) AS 'weekday',
    COUNT(order_id) AS pizza_ordered
FROM
    #customer_orders_temp
GROUP BY DATENAME(DW, order_time)
ORDER BY pizza_ordered DESC;



/*RUNNER AND CUSTOMER EXPERIENCE*/
--How many runners signed up for each 1 week period? (i.e. week starts 2021-01-01)
SELECT 
  DATEPART(week, registration_date) AS week_period,
  COUNT(*) AS runner_count
FROM runners
GROUP BY DATEPART(week, registration_date);

--What was the average time in minutes it took for each runner to arrive at the Pizza Runner HQ to pickup the order?
WITH runners_pickup AS (
  SELECT
    r.runner_id,
    c.order_id, 
    c.order_time, 
    r.pickup_time, 
    DATEDIFF(MINUTE, c.order_time, r.pickup_time) AS pickup_minutes
  FROM #customer_orders_temp AS c
  JOIN #runner_orders_temp AS r
    ON c.order_id = r.order_id
  WHERE r.cancellation IS NULL
  GROUP BY r.runner_id, c.order_id, c.order_time, r.pickup_time
)

SELECT 
  runner_id,
  AVG(pickup_minutes) AS average_time
FROM runners_pickup
GROUP BY runner_id;


--Is there any relationship between the number of pizzas and how long the order takes to prepare?
WITH pizzaPrepration AS (
  SELECT
    c.order_id, 
    c.order_time, 
    r.pickup_time,
    DATEDIFF(MINUTE, c.order_time, r.pickup_time) AS prep_time,
    COUNT(c.pizza_id) AS pizza_count
  FROM #customer_orders_temp AS c
  JOIN #runner_orders_temp AS r
    ON c.order_id = r.order_id
  WHERE r.cancellation IS NULL
  GROUP BY c.order_id, c.order_time, r.pickup_time, 
           DATEDIFF(MINUTE, c.order_time, r.pickup_time)
)

SELECT 
  pizza_count,
  AVG(prep_time) AS avg_prep_time
FROM pizzaPrepration
GROUP BY pizza_count;


--What was the average distance travelled for each customer?
SELECT
  c.customer_id,
  ROUND(AVG(r.distance), 1) AS average_distance
FROM #customer_orders_temp AS c
JOIN #runner_orders_temp AS r
  ON c.order_id = r.order_id
GROUP BY c.customer_id;

--What was the difference between the longest and shortest delivery times for all orders?
SELECT 
    MAX(duration) - MIN(duration) AS duration_difference
FROM
    #runner_orders_temp;

 --What was the average speed for each runner for each delivery and do you notice any trend for these values?
SELECT 
  r.runner_id,
  c.order_id,
  r.distance,
  r.duration AS duration_in_min,
  COUNT(c.order_id) AS number_of_pizza, 
  ROUND(AVG(r.distance/r.duration*60), 1) AS avg_speed
FROM #runner_orders_temp r
JOIN #customer_orders_temp c
  ON r.order_id = c.order_id
WHERE r.cancellation IS NULL
GROUP BY r.runner_id, c.order_id, r.distance, r.duration;

--What is the successful delivery percentage for each runner?
SELECT runner_id,COUNT(*) AS total_orders,COUNT(distance) AS delivered, ROUND(100 * SUM(
	CASE WHEN distance IS NULL THEN 0 
	ELSE 1
	END) / COUNT(*), 0) AS success_percentage
FROM #runner_orders_temp
GROUP BY runner_id;


                   /*INGREDIENTS OPTIMISATION
Data cleaning
Create a new temporary table #toppingspivot to separate toppings into multiple rows*/
SELECT
    pr.pizza_id,
    CAST(value AS INT) AS topping_id, pt.topping_name
INTO #toppingspivot
FROM
    pizza_recipes pr
CROSS APPLY
    STRING_SPLIT(CAST(pr.toppings AS NVARCHAR(MAX)), N',')
 JOIN pizza_toppings pt
  ON CAST(value AS INT) = pt.topping_id;

SELECT *
FROM #toppingspivot;

--Add a helper/identity column record_id to #customer_orders_temp to select each ordered pizza more easily
ALTER TABLE #customer_orders_temp
ADD record_id INT IDENTITY(1,1);

SELECT *
FROM #customer_orders_temp

--Create a new temporary table #extraspivot to separate extras into multiple rows
SELECT 
  c.record_id,
  TRIM(e.value) AS extra_id
INTO #extraspivot
FROM #customer_orders_temp c
  CROSS APPLY STRING_SPLIT(extras, ',') AS e;

SELECT *
FROM #extraspivot;

-- Create a new temporary table #exclusionspivot to separate into exclusions into multiple rows
SELECT 
  c.record_id,
  TRIM(e.value) AS exclusion_id
INTO #exclusionspivot
FROM #customer_orders_temp c
  CROSS APPLY STRING_SPLIT(exclusions, ',') AS e;

SELECT *
FROM #exclusionspivot;

--What are the standard ingredients for each pizza?
SELECT
    pr.pizza_id,
    STRING_AGG(CONVERT(NVARCHAR(MAX), pt.topping_name), ', ') AS standard_ingredients
FROM
    pizza_recipes pr
JOIN
    #toppingspivot tp ON pr.pizza_id = tp.pizza_id
JOIN
    pizza_toppings pt ON tp.topping_id = pt.topping_id
GROUP BY
    pr.pizza_id
ORDER BY
    pr.pizza_id;

-- What was the most commonly added extra?
SELECT 
  p.topping_name,
  COUNT(*) AS extra_count
FROM #extraspivot e
JOIN pizza_toppings p
  ON e.extra_id = p.topping_id
GROUP BY p.topping_name
ORDER BY COUNT(*) DESC;

-- What was the most common exclusion?

SELECT 
  p.topping_name,
  COUNT(*) AS exclusion_count
FROM #exclusionspivot e
JOIN pizza_toppings p
  ON e.exclusion_id = p.topping_id
GROUP BY p.topping_name
ORDER BY COUNT(*) DESC;


/*Generate an order item for each record in the customers_orders table in the format of one of the following
Meat Lovers
Meat Lovers - Exclude Beef
Meat Lovers - Extra Bacon
Meat Lovers - Exclude Cheese, Bacon - Extra Mushroom, Peppers

To solve this question:
Create 3 CTEs: extras_cte, exclusions_cte, and union_cte combining two tables
Use the union_cte to LEFT JOIN with the customer_orders_temp and JOIN with the pizza_name
Use the CONCAT_WS with STRING_AGG to get the result*/

WITH ingredients AS (
  SELECT 
    c.*,
    p.pizza_name,

    -- Add '2x' in front of topping_names if their topping_id appear in the #extraspivottable
    CASE WHEN t.topping_id IN (
          SELECT extra_id 
          FROM #extraspivot e 
          WHERE e.record_id = c.record_id)
      THEN '2x' + t.topping_name
      ELSE t.topping_name
    END AS topping

  FROM #customer_orders_temp c
  JOIN #toppingspivot t
    ON t.pizza_id = c.pizza_id
  JOIN pizza_names p
    ON p.pizza_id = c.pizza_id

  -- Exclude toppings if their topping_id appear in the #exclusionBreak table
  WHERE t.topping_id NOT IN (
      SELECT exclusion_id 
      FROM #exclusionspivot e 
      WHERE c.record_id = e.record_id)
)

SELECT 
  record_id,
  order_id,
  customer_id,
  pizza_id,
  order_time,
  CONCAT(pizza_name + ': ', STRING_AGG(topping, ', ')) AS ingredients_list
FROM ingredients
GROUP BY 
  record_id, 
  record_id,
  order_id,
  customer_id,
  pizza_id,
  order_time,
  pizza_name
ORDER BY record_id;


/*What is the total quantity of each ingredient used in all delivered pizzas sorted by most frequent first?
To solve this question:

Create a CTE to record the number of times each ingredient was used
if extra ingredient, add 2
if excluded ingredient, add 0
no extras or no exclusions, add 1*/
WITH frequentIngredients AS (
  SELECT 
    c.record_id,
    t.topping_name,
    CASE
      -- if extra ingredient, add 2
      WHEN t.topping_id IN (
          SELECT extra_id 
          FROM #extraspivot e
          WHERE e.record_id = c.record_id) 
      THEN 2
      -- if excluded ingredient, add 0
      WHEN t.topping_id IN (
          SELECT exclusion_id 
          FROM #exclusionspivot e 
          WHERE c.record_id = e.record_id)
      THEN 0
      -- no extras, no exclusions, add 1
      ELSE 1
    END AS times_used
  FROM #customer_orders_temp c
  JOIN #toppingspivot t
    ON t.pizza_id = c.pizza_id
  JOIN pizza_names p
    ON p.pizza_id = c.pizza_id
)

SELECT 
  topping_name,
  SUM(times_used) AS times_used 
FROM frequentIngredients
GROUP BY topping_name
ORDER BY times_used DESC;


                /*PRICING AND RATINGS*/
--If a Meat Lovers pizza costs $12 and Vegetarian costs $10 and there were no charges for changes - how much money has Pizza Runner made so far if there are no delivery fees?
SELECT
  SUM(CASE WHEN CAST(p.pizza_name AS VARCHAR(255)) = 'Meatlovers' THEN 12
        ELSE 10 END) AS revenue
FROM #customer_orders_temp c
JOIN pizza_names p
  ON c.pizza_id = p.pizza_id
JOIN #runner_orders_temp r
  ON c.order_id = r.order_id
WHERE r.cancellation IS NULL;

/*What if there was an additional $1 charge for any pizza extras?
Add cheese is $1 extra*/
DECLARE @basecost INT
SET @basecost = 138 	-- @basecost = result of the previous question

SELECT 
  @basecost + SUM(CASE WHEN CAST(p.topping_name AS VARCHAR(255)) = 'Cheese' THEN 2
		  ELSE 1 END) updated_revenue
FROM #extraspivot e
JOIN pizza_toppings p
  ON e.extra_id = p.topping_id;

--The Pizza Runner team now wants to add an additional ratings system that allows customers to rate their runner, how would you design an additional table for this new dataset - generate a schema for this new table and insert your own data for ratings for each successful customer order between 1 to 5.
DROP TABLE IF EXISTS pizza_ratings
CREATE TABLE pizza_ratings (
  order_id INT,
  customer_id int,
  rating INT);
INSERT INTO pizza_ratings
VALUES 
  (1, 101, 3),
  (2, 101, 2),
  (3, 102, 3),
  (4, 103, 2),
  (5, 104, 1),
  (7, 105, 1),
  (8, 102, 4),
  (10, 104, 3);

 SELECT *
 FROM pizza_ratings;

 /*Using your newly generated table - can you join all of the information together to form a table which has the following information for successful deliveries?
customer_id
order_id
runner_id
rating
order_time
pickup_time
Time between order and pickup
Delivery duration
Average speed
Total number of pizzas*/
SELECT 
  c.customer_id,
  c.order_id,
  r.runner_id,
  pizza_ratings,
  c.order_time,
  r.pickup_time,
  DATEDIFF(MINUTE, c.order_time, r.pickup_time) AS mins_difference,
  r.duration,
  ROUND(AVG(r.distance/r.duration*60), 1) AS avg_speed,
  COUNT(c.order_id) AS pizza_count
FROM #customer_orders_temp c
JOIN #runner_orders_temp r 
  ON r.order_id = c.order_id
GROUP BY 
  c.customer_id,
  c.order_id,
  r.runner_id,
  c.order_time,
  r.pickup_time, 
  r.duration;

--If a Meat Lovers pizza was $12 and Vegetarian $10 fixed prices with no cost for extras and each runner is paid $0.30 per kilometre traveled - how much money does Pizza Runner have left over after these deliveries?
DECLARE @basecost INT
SET @basecost = 138

SELECT 
  @basecost AS revenue,
  SUM(distance)*0.3 AS runners_paid,
  @basecost - SUM(distance)*0.3 AS change_left
FROM #runner_orders_temp;

                               /*Bonus Question*/
--If Danny wants to expand his range of pizzas - how would this impact the existing data design? Write an INSERT statement to demonstrate what would happen if a new Supreme pizza with all the toppings was added to the Pizza Runner menu?
INSERT INTO pizza_names (pizza_id, pizza_name)
VALUES (3, 'Supreme');

ALTER TABLE pizza_recipes
ALTER COLUMN toppings VARCHAR(50);

INSERT INTO pizza_recipes (pizza_id, toppings)
VALUES (3, '1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12');
