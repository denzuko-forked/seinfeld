$: << File.join(File.dirname(__FILE__), '..', '..', 'vendor', 'feed_me', 'lib')
require 'rubygems'
require 'open-uri'
require 'dm-core'
require 'feed_me'
require 'set'

module Seinfeld
  class User
    include DataMapper::Resource
    property :id,    Integer, :serial => true
    property :login, String
    property :email, String
    property :last_entry_id, String
    has n, :progressions, :class_name => "Seinfeld::Progression", :order => [:created_at.desc]

    def self.paginated_each(&block)
      max_id = 0
      while batch = next_batch(max_id)
        batch.each(&block)
        max_id = batch.map { |u| u.id }.max
      end
    end

    def self.next_batch(id)
      batch = all :order => [:id], :limit => 15, :id.gt => id
      batch.size.zero? ? nil : batch
    end

    def update_progress
      transaction do
        save if new_record?
        days = committed_days_in_feed
        save
        unless days.empty?
          existing = progressions(:created_at => days).map { |p| p.created_at }
          (days - existing).each do |day|
            progressions.create(:created_at => day)
          end
        end
      end
    end

    def committed_days_in_feed(page = 1)
      feed     = get_feed(page)
      entry_id = nil # track the first entry id to store in the user model
      days = feed.entries.inject({}) do |selected, entry|
        this_entry_id = entry.item_id
        if last_entry_id == this_entry_id
          break selected
        end
        entry_id ||= this_entry_id

        if entry.title =~ %r{^#{login} committed}
          updated = entry.updated_at
          date    = Time.utc(updated.year, updated.month, updated.day)
          selected.update date => nil
        else
          selected
        end
      end.keys.sort
      self.last_entry_id = entry_id
      days
    end

    def progress_for(year, month)
      start = Date.new(year, month)
      Set.new progressions(:created_at => start..(start >> 1)).map { |p| Date.new(p.created_at.year, p.created_at.month, p.created_at.day) }
    end

  private
    def get_feed(page = 1)
      feed = nil
      open("http://github.com/#{login}.atom?page=#{page}") { |f| feed = FeedMe.parse(f.read) }
      feed
    end
  end

  class Progression
    include DataMapper::Resource
    property :id,         Integer, :serial => true
    property :created_at, DateTime
    belongs_to :user, :class_name => "Seinfeld::User"
  end
end