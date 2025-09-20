# SQL Date Interval Set Operations

## Some Background

Algorithms for finding intervals are sometimes referred to as *Packing Intervals* or *Gaps and Islands* problems. However, in code solutions and functional programming this is more often referred to as merging or flattening the intervals.

## Flattening, Differencing, & Intersecting: an Optimization Story

I worked on a system that calculated date intervals for qualification and eligibility for almost a decade before I learned the term *Gaps and Islands*. During that time I'd already iterated through a few different solutions in T-SQL, particulary spurred on by the need to improve the performance of these queries as the system scaled to handing over a million accounts, each with potentially dozens of intervals.

Fast forward to November 2018, after years of peak seasonal work conflicts (e.g. Medicare annual enrollment) I was finally able to attend PASS Summit for the first time, and on the company's dime. While there, I attended several of Itzik Ben-Gan's sessions. After one of these, we got to talking about temporal tables and Microsoft's implementation as system-versioned tables, which I'd hand-rolled my own version of back in 2010 based on Chris Date's writings on temporal relational theory. Afterwards, Itzik ended up giving me a free copy of his "Window Functions 2012" book.

I was a little busy the next few months, having gotten engaged shortly after returning from the conference, so I didn't start reading this book until the end of January 2019 and then took a month to finish it. After reading the section in chapter 5 on packing intervals, I searched online for articles about similar problems, and started experimenting with my own solutions.

First, I refactored some core queries that flattened date intervals to use this new-to-me approach of using a cummulative sum to track the unique start and end boundaries of the intervals. I was able to demonstrate that it would significantly reduce execution times, shaving several minutes off of each query run, multiplied across several different parts of the process. See [simple-date-interval-flattening.sql](./simple-date-interval-flattening.sql).

Next, I tackled a more challenging scenario: flattening and differencing at the same time. See, part of our qualification rules involved intervals where a condition was met that prevented qualification. So, we needed queries to flatten the intervals that met qualification and difference out the excluded condition intervals at the same time. My previous approach required first separately flattening the positive intervals and the excluded intervals, then calculating all of the adjusted positive intervals, which was relatively expensive. It took some experimenting, but I came up with a way to track both positive and negative interval cumulative sums to identify the start and end boundaries in a single pass. This shaved off several more minutes from the total execution time, although this query pattern appeared in less places and thus did not result in as significant of an improvement overall. See [simple-date-interval-flattening-and-differencing.sql](./simple-date-interval-flattening-and-differencing.sql). A similar approach works for intersecting date intervals from 2 sets; see [simple-date-interval-flattening-and-intersecting.sql](./simple-date-interval-flattening-and-intersecting.sql).

Finally, I tackled the most complex scenario within this process: flattening and intersecting at the same time, while keeping additional attributes from the end boundary based on a tie-breaker. Up to this point, the solution involved identifying groups of unique start and end boundaries and using `MIN` and `MAX` to pull out the start and end dates from the grouping. However, this scenario meant that grouping in this way was no longer viable. It took some more experimenting, but eventually I realized that the same logic that was calculating the `groupingId`'s using division (`/ 2`) could be altered to identify output boundary types using modulo (`% 2`) instead. `LAG` could then be used to "pull forward" the date from the prior filtered boundary as the start date for the "end" record. Then a final filtering to only return the end boundary rows with their associated start dates resulted in the desired rows with the additional end boundary attributes passed along. The same approach could be reversed if the desired attributes to keep were associated with the start boundary instead. This solution allowed a query that had been running for 45+ minutes to complete in between 30 seconds and 1.5 minutes on average. See [advanced-date-interval-flattening-and-intersecting.sql](./advanced-date-interval-flattening-and-intersecting.sql). A similar approach works for differencing and keeping additional attributes; see [advanced-date-interval-flattening-and-differencing.sql](./advanced-date-interval-flattening-and-differencing.sql).

In the end, using these query patterns for flattening and differencing date intervals in a single pass allowed a process that had been averaging 1-1.5 hours, and occasionally running for 3-4 hours, to consistently run in under 15 minutes, with an average between 8-12 minutes.

---

## References

Here are some of the resources that influenced my approach, including some newer articles on the topic. To be clear, my primary inspiration came from Itzik Ben-Gan's writings:

- [Microsoft SQL Server 2012 High-Performance T-SQL Using Window Functions](https://itziktsql.com/t-sql-winfun-3) by Itzik Ben-Gan, April 2012
  - Book: chapter 5, packing intervals
  - *I read this in February 2019. Itzik gave it to me at PASS Conference in November 2018 after one of his sessions. This is what inspired by approach, as it gave me another term, Gaps and Islands, for searching for other implementations, and ultimately inspired my solution.*

- [Gaps and Islands in SQL Server data](https://www.red-gate.com/simple-talk/databases/sql-server/t-sql-programming-sql-server/gaps-islands-sql-server-data/) by Dwain Champs, July 25, 2013
  - Has great performance comparisons between alternate solutions.

- [Calculating Gaps Between Overlapping Time Intervals in SQL](https://www.red-gate.com/simple-talk/databases/sql-server/t-sql-programming-sql-server/calculating-gaps-between-overlapping-time-intervals-in-sql/) by Itzik Ben-Gan, February 14, 2014
  - There are a lot of links at the end to other related aricles and blogs. Most of which are also by Itzik Ben-Gan. However, it appears that several of these links are now broken...

- [Special Islands](https://sqlperformance.com/2018/09/t-sql-queries/special-islands) by Itzik Ben-Gan, September 12, 2018

- [Reader solutions to Special Islands challenge](https://sqlperformance.com/2018/10/sql-performance/reader-solutions-islands-challenge) by Itzik Ben-Gan, October 10, 2018

- [Islands T-SQL Challenge](https://sqlperformance.com/2022/04/t-sql-queries/islands-t-sql-challenge) by Itzik Ben-Gan, April 13, 2022
  - *I read this more recently (in 2025), well after my work on date interval queries. It provides a good performance comparisons with a non-windowing approach.*

- [Introduction to Gaps and Islands Analysis](https://www.red-gate.com/simple-talk/databases/sql-server/t-sql-programming-sql-server/introduction-to-gaps-and-islands-analysis/) by Edward Pollock, January 2, 2020

- [Two-Dimensional Interval Packing Challenge](https://www.red-gate.com/simple-talk/databases/sql-server/t-sql-programming-sql-server/two-dimensional-interval-packing-challenge/) by Itzik Ben-Gan, January 2, 2024
  - Includes newer T-SQL language features, such as `GENERATE_SERIES`.
  - *I haven't read through the whole thing yet, but it looks interesting.*

I've been informed that this approach is similar to a Static Relational Interval Tree (aka Static RI-Tree, SRIT). As such, for completeness and transparency, here are some additional links if you would like to read further and compare approaches:

- [Managing Intervals Efficiently in Object-Relational Databases](https://www.dbs.ifi.lmu.de/Publikationen/Papers/VLDB2000.pdf) by Hans-Peter Kriegel, Marco Pötke, Thomas Seidl, VLDB 2000
  - Also available on [vldb.org](https://www.vldb.org/conf/2000/P407.pdf).
- [Additional Intervals whitepapers and articles](https://itziktsql.com/r-whitepapers-%2F-articles) by Itzik Ben-Gan and Laurent Martin
  - Laurent Martin's articles reference Hans-Peter Kriegel, Marco Pötke, Thomas Seidl's paper
- [Efficiently Processing Queries on Interval-and-Value Tuples in Relational Databases](https://www.researchgate.net/publication/221310875_Efficiently_Processing_Queries_on_Interval-and-Value_Tuples_in_Relational_Databases) by Jost Enderle, Nicole Schneider, Thomas Seidl, VLDB 2005
- [Interval tree](https://en.wikipedia.org/wiki/Interval_tree) on Wikipedia

---
&copy; 2025 Joel Searcy. All rights reserved.
