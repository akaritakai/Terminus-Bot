

#
# Terminus-Bot: An IRC bot to solve all of the problems with IRC bots.
# Copyright (C) 2011 Terminus-Bot Development Team
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program. If not, see <http://www.gnu.org/licenses/>.
#


module Terminus_Bot

  class Bot

    attr_reader :config, :connections, :events, :database, :commands, :script_info, :scripts

    VERSION = "Terminus-Bot v0.5"

    Command = Struct.new(:owner, :cmd, :func, :argc, :level, :help)
    Script_Info = Struct.new(:name, :description)

    # This starts the whole thing.
    def initialize

      # Dirty? A bit. TODO: Get rid of this. Maybe.
      $bot = self

      @connections = Hash.new       # IRC objects. Keys are configured names.

      @config = Configuration.new   # Configuration. Extends Hash.

      @database = Database.new      # Scripts can store data here.

      @commands = Array.new         # An array of Commands (see the above Struct).
                                    # These are fired like events.
      
      @script_info = Array.new      # Name and description for scripts (see above Struct).

      @events = Events.new          # We're event-driven. See includes/event.rb

      @scripts = Scripts.new        # For those things in the scripts dir.

      
      # The only event we care about in the core.
      @events.create(self, "PRIVMSG", :run_commands)

      # Iterate through the configured networks and connect to each
      # of them, populating the @connections hash table.
      config['core']['servers'].split(" ").each do |server_config|
        server_config = server_config.split(":")

        $log.debug("Bot.initialize") { "Working on server config for #{server_config[0]}" }

        if @connections.has_key? server_config[0]
          throw "Duplicate server name."
        end

        # Actually start the connection. Once connected, this will kick off
        # threads for listening and sending data. If it fails, the bot will
        # probably take a fatal error.
        @connections[server_config[0]] = IRC::Connection.new(server_config[0],
                                                             server_config[1],
                                                             server_config[2],
                                                             config["core"]["bind"],
                                                             server_config[3],
                                                             config["core"]["nick"],
                                                             config["core"]["user"],
                                                             config["core"]["realname"])
      end

      # Since we made it this far, go ahead and be ready for signals.
      trap("INT")  { quit("Interrupted by host system. Exiting!") }
      trap("TERM") { quit("Terminated by host system. Exiting!") }
      trap("KILL") { exit }
      
      trap("HUP", $bot.config.read_config ) # Rehash on HUP!
      
      # Try to exit cleanly if we have to.
      at_exit { quit }

      # TODO: Do something different. This is kind of dumb.
      @connections.values.last.read_thread.join
    end

    # Fired on PRIVMSGs.
    # Iterate through @commands and run everything that needs to be run.
    def run_commands(msg)
      return unless msg.text =~ /\A#{msg.private? ?
        '(' + @config['core']['prefix'] + ')?' :
        '(' + @config['core']['prefix'] + ')'}([^ ]+)(.*)\Z/

      $log.debug("Bot.run_commands") { "Running command #{$2} from #{msg.origin}" }

      @commands.each do |command|
        $log.debug("Bot.run_commands") { "Checking #{command.cmd}" }

        if command.cmd == $2

          level = msg.connection.users.get_level(msg)

          if command.level > level
            msg.reply("Level \02#{command.level}\02 authorization required. (Current level: #{level})")
            return
          end

          params = Array.new
          params_raw = $3.strip.split(" ")

          if params_raw.length < command.argc
            msg.reply("This command requires at least \02#{command.argc}\02 parameters.")
            return
          end

          (0..command.argc - 1).each do |i|
            if i == command.argc - 1
              params << params_raw[i..params_raw.length-1].join(" ")
            else
              params << params_raw[i]
            end
          end

          $log.debug("Bot.run_commands") { "Match for command #{$2} in #{command.owner}" }

          begin
            command.owner.send(command.func, msg, params)
            return
          rescue => e
            $log.error("Bot.run_commands") { "Problem running command #{$2} in #{command.owner}: #{e}" }
            msg.reply("There was a problem running your command: #{e}")
          end

        end

      end
    end

    # Send QUITs and do any other work that needs to be done before exiting.
    def quit(str = "Terminus-Bot: Terminating")
      @connections.each_value do |connection|
        connection.disconnect(str)
      end

      exit
    end

    # Register a command. See the Commands struct for the args.
    def register_command(*args)
      $log.debug("Bot.register_command") { "Registering command." }

      @commands << Command.new(*args)
    end

    # Register a script. See the Script_Info struct for args.
    def register_script(*args)
      $log.debug("Bot.register_script") { "Registering script." }

      @script_info << Script_Info.new(*args)
    end

    # Remove a script from @scripts (by name).
    def unregister_script(name)
      $log.debug("Bot.unregister_script") { "Unregistering script #{name}" }
      @script_info.delete_if {|s| s.name == name}
    end

    # Unregister a specific command. This doesn't check for ownership
    # and removes all matching commands by name.
    def unregister_command(cmd)
      $log.debug("Bot.unregister_command") { "Unregistering command #{cmd}" }
      @commands.delete_if {|c| c.cmd == cmd}
    end

    # Unregister all commands owned by the given class.
    def unregister_commands(owner)
      $log.debug("Bot.unregister_commands") { "Unregistering all commands for #{owner.class.name}" }
      @commands.delete_if {|c| c.owner == owner}
    end

    # Unregister all events owned by the given class.
    def unregister_events(owner)
      $log.debug("Bot.unregister_events") { "Unregistering all events for #{owner.class.name}" }
      @events.delete_events_for(owner)
    end

  end

end