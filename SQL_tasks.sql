-- Посчитаем разницу между максимальной и минимальной установленной ценой у каждого хозяина.

-- host_id – идентификатор хозяина
-- id – идентификатор жилья
-- price – цена за ночь в конкретном месте

SELECT
    host_id,
    groupArray(id) as hosts,
    (max(toFloat64OrNull(replaceRegexpAll(price, '[$,]', ''))) as MaxPricePerHost) -
    (min(toFloat64OrNull(replaceRegexpAll(price, '[$,]', ''))) as MinPricePerHost) as diff_prices
FROM listings
group by host_id
ORDER BY diff_prices desc
LIMIT 200


-- Сначала оставьте только те объявления, где оценка на основе отзывов выше среднего, а число отзывов в месяц
-- составляет строго меньше трёх. Затем отсортируйте по убыванию две колонки: сначала по числу отзывов в месяц, потом по оценке.

-- review_scores_rating – оценка на основе отзывов
-- reviews_per_month – число отзывов в месяц
-- id – идентификатор объявления

SELECT host_id,
       room_type,
       longitude,
       latitude,
       geoDistance(13.4050, 52.5200, toFloat64OrNull(longitude), toFloat64OrNull(latitude)) as dist
FROM listings
WHERE dist < (
    SELECT AVG(geoDistance(13.4050, 52.5200, toFloat64OrNull(longitude),
                           toFloat64OrNull(latitude))) as AvgDist
    FROM listings
    WHERE room_type = 'Private room'
)
  AND room_type = 'Private room'
ORDER BY dist DESC
LIMIT 10


-- Представим, что вы планируете снять жилье в Берлине на 7 дней, используя более хитрые фильтры, чем предлагаются на сайте.
-- Отберите объявления из таблицы listings, которые:
-- находятся на расстоянии от центра меньше среднего, обойдутся дешевле 100$ в день (с учетом cleaning_fee,
-- которая добавляется к общей сумме за неделю, т.е ее нужно делить на кол-во дней),
-- имеют последние отзывы (last_review) начиная с 1 сентября 2018 года и WiFi в списке удобств (amenities)


SELECT host_id,
       toFloat64OrNull(review_scores_rating) AS review_scores_rating,
       near_center.price+(cleaning_fee_num/7) AS all_price, -- цена за день, включая уборку
    last_review,
        amenities
FROM default.listings
         JOIN (
    SELECT host_id,
           room_type,
           longitude,
           latitude,
           geoDistance(13.4050, 52.5200, toFloat64OrNull(longitude), toFloat64OrNull(latitude)) AS dist,
           toFloat64OrNull(replaceRegexpAll(price, '[$,]', '')) AS price,
           toFloat64OrNull(replaceRegexpAll(cleaning_fee, '[$,]', '')) AS cleaning_fee_num
    FROM listings
    WHERE dist < (
        SELECT AVG(geoDistance(13.4050, 52.5200, toFloat64OrNull(longitude),
            toFloat64OrNull(latitude))) AS AvgDist
        FROM listings
        WHERE room_type = 'Private room'
    )
      AND room_type = 'Private room'
    ORDER BY dist DESC
) AS near_center
              ON listings.host_id = near_center.host_id
WHERE all_price < 100 -- дешевле 100 в день
    AND last_review >= '01.09.2018' -- последние отзывы с 1 сентября 2018
    AND multiSearchAnyCaseInsensitive(amenities, ['WiFi']) != 0  -- WiFi в списке удобств
ORDER BY review_scores_rating desc


-- Давайте найдем в таблице calendar_summary те доступные (available='t') объявления, у которых число отзывов
-- от уникальных пользователей в таблице reviews выше среднего.
-- Для этого посчитайте среднее число уникальных reviewer_id из таблицы reviews на каждое жильё,
-- объедините calendar_summary и reviews (при этом из таблицы calendar summary должны быть отобраны
-- уникальные listing_id, отфильтрованные по правилу available='t').
-- Результат отфильтруйте так, чтобы остались только записи, у которых число отзывов от уникальных людей выше среднего.

-- найдем среднее число уникальных ревьюеров на каждое жилье
with (
    select avg(count_unique_authors)
    from (
             select count(DISTINCT reviewer_id) as count_unique_authors, count(DISTINCT listing_id) as unique_reviewers
             from reviews
             group by listing_id)
) as avg_unique_authors
-- = 21.40

-- соединим таблицы по listing_id
select count(DISTINCT reviewer_id) as unique_reviews, listing_id
from (
         select DISTINCT listing_id
         from calendar_summary
         where available = 't'
     ) as listing_id_t -- отбираем только те listing_id, где true
left join default.reviews
on listing_id_t.listing_id = reviews.listing_id
where reviewer_id > avg_unique_authors
group by listing_id
order by listing_id
limit 10

-- Cколько клиентов приходится на каждый сегмент и сколько доходов он приносит

-- сколько клиентов в каждом сегменте, сегмент, доход по сегменту
select count(distinct UserID) as users,
       segment,
       sum(Rub) as sum_rub
from (
         -- создаем сами сегменты (юзер - сегмент)
    select distinct UserID,
        CASE
            WHEN AVG(Rub) < 5 THEN 'A'
            WHEN AVG(Rub) >= 5 AND AVG(Rub) < 10 THEN 'B'
            WHEN AVG(Rub) >= 10 AND AVG(Rub) < 20 THEN 'C'
            ELSE 'D'
        END AS segment
    from checks
    group by UserID
    order by UserID
    ) as user_segments
         join default.checks on user_segments.UserID = checks.UserID
group by segment
order by sum_rub desc


-- Давайте посмотрим на продажи авокадо в двух городах (NewYork, LosAngeles) и узнаем,
-- сколько авокадо типа organic было продано в целом к концу каждой недели (накопительная сумма продаж),
-- начиная с начала периода наблюдений (04/01/15).

SELECT region,
    date,
    total_volume,
    SUM(total_volume) OVER w AS volume
FROM avocado
WHERE region in ('NewYork', 'LosAngeles')
  and type = 'organic'
    #and date >= '04/01/15'
    WINDOW w AS (
    PARTITION BY region
    ORDER BY date
    ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    )
ORDER BY region DESC, date