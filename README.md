# 📊 India Job Market Intelligence Platform

Scraping → Warehousing → SQL Analytics → Power BI Dashboard
A real-time analytics platform that tracks skill demand, hiring trends, and salary intelligence across India's top tech hubs — built entirely on live Naukri.com data.


### What This Project Does
This project scrapes live job listings weekly, stores them in a normalized MySQL star schema, computes 6 analytical metrics using SQL window functions, CASE WHEN and visualizes everything in an interactive single-page Power BI dashboard.
The dashboard answers questions that HR teams, L&D departments, and job seekers actually pay for:

1. Which skills are rising or declining in demand this week?
2. Which city + role combination has the most fresher openings?
3. Which skill pairs always appear together in job descriptions?
4. Which roles are hardest to fill in each city?
   
### TOOLS
Python, Selenium, BeautifulSoup, MySQL 8.0 (Star Schema), Pandas, NumPy, Power BI Desktop, Jupyter Notebook , MySQL Views + Window Functions.

## Dashboard
Single-page interactive Power BI dashboard with 3 dynamic slicers (City / Role / Experience) that filter all visuals simultaneously.
KPI Cards(4), Top Skills Bar Chart, Skill Co-occurrence Matrix , etc 
