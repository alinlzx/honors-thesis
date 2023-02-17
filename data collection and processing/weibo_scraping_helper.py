import pandas as pd
from weibo_scraper import get_weibo_tweets_by_name
from weibo_scraper import get_weibo_profile


def get_weibo_username(userid):

    weibo_profile = get_weibo_profile(uid = userid)
    print(weibo_profile.followers_count)

    userid = weibo_profile.screen_name

    return userid


def scrape(corpus, username):

    i = 0
    for tweet in get_weibo_tweets_by_name(name=username, pages=1):
        #corpus[tweet["itemid"]] = tweet
        i += 1
        if i >= 1:
            print(tweet)
            #print(tweet.keys())
            break

    return corpus

