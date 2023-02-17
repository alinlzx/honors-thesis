from weibo_scraping_helper import scrape
from weibo_scraping_helper import get_weibo_username


def main():

    userid = "6651523309"

    corpus = dict()

    username = get_weibo_username(userid)

    scrape(corpus, username)

    # print(len(corpus))


if __name__ == '__main__':
    main()


