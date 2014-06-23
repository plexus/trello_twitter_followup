#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'trello'
require 'twitter'
require 'yaml'

TRELLO_DEVELOPER_PUBLIC_KEY = "..."
TRELLO_MEMBER_TOKEN         = "..."

TWITTER_CONSUMER_KEY        = "..."
TWITTER_CONSUMER_SECRET     = "..."
TWITTER_ACCESS_TOKEN        = "..."
TWITTER_ACCESS_TOKEN_SECRET = "..."

BOARD_NAME = 'Twitter Followup'
BOARD_DESC = 'Handling mentions on Twitter'
LIST_NAMES = ['Incoming', 'Positive', 'Neutral', 'Negative']

Trello.configure do |trello|
  trello.developer_public_key = TRELLO_DEVELOPER_PUBLIC_KEY
  trello.member_token = TRELLO_MEMBER_TOKEN
end

def twitter_client
  Twitter::Streaming::Client.new do |config|
    config.consumer_key        = TWIITER_CONSUMER_KEY
    config.consumer_secret     = TWIITER_CONSUMER_SECRET
    config.access_token        = TWIITER_ACCESS_TOKEN
    config.access_token_secret = TWIITER_ACCESS_TOKEN_SECRET
  end
end

board = Trello::Board.all.detect do |board|
  board.name == BOARD_NAME
end

unless board
  board = Trello::Board.create(
    name: BOARD_NAME,
    description: BOARD_DESC
  )
  board.lists.each(&:close!)

  LIST_NAMES.reverse.each do |name|
    Trello::List.create(name: name, board_id: board.id)
  end

  board.lists.drop(1).each do |list|
    Trello::Card.create(list_id: list.id, name: '[0]')
  end
end

def score_lists(board)
  LIST_NAMES.drop(1).map do |name|
    board.lists.find { |list| list.name == name }
  end
end

def find_score_card(list)
  list.cards.find do |card|
    card.name =~ /\A\[\d+\]\z/
  end
end

def listen_to_tweets(board, twitter_client, topics)
  incoming_list = board.lists.first

  twitter_client.filter(:track => topics.join(",")) do |object|
    if object.is_a?(Twitter::Tweet)
      Trello::Card.create(
        list_id: incoming_list.id,
        name: object.text,
        desc: object.url.to_s
      )
    end
  end
end

def process_card(card, score_card)
  old_score = score_card.name[/\d+/].to_i
  new_score = old_score + 1

  tweet_text = card.name
  tweet_link = card.desc

  score_card.name = "[#{new_score}]"
  score_card.desc = "* #{tweet_text} [↗](#{tweet_link}) \n" + score_card.desc

  card.closed = true

  [card, score_card].each(&:save)
end

def process_sorted_cards(board)
  score_lists(board).each do |list|
    score_card = find_score_card(list)
    list.cards.each do |card|
      unless card.id == score_card.id
        process_card(card, score_card)
      end
    end
  end
end

case ARGV[0]
when 'stream'
  topics = ARGV.drop(1)
  listen_to_tweets(board, twitter_client, topics)
when 'process'
  loop do
    process_sorted_cards(board)
    sleep 5
  end
end
