namespace :uva do
  namespace :migrate do
    desc "Convert ALL custom mods fields"
    task :all_mods_roles => :environment do
      puts "Migrating all custom Mods roles in 5 seconds..."
      sleep(5)

      MediaObject.find_each({},{batch_size:5}) do |mo|
        convert_custom_name_roles(mo)
      end
    end

    desc "Convert one custom mods field"
    task :one_mods_roles => :environment do
      if ENV['ID'].blank?
        puts "Include a Media Object Id with this format: rake uva:migrate:one_mods_roles ID=xxxxxxx "
        return
      end

      mo = MediaObject.find(ENV['ID'])
      puts "Migrating #{mo.inspect}\nin 5 seconds..."
      sleep(5)

      convert_custom_name_roles(mo)
    end


    private
    def convert_custom_name_roles(mo)

      puts "#{mo.id} Processing"
      doc = mo.descMetadata.ng_xml
      modified = false

      # Select direct descendent of <mods>, <name> only
      doc.css('mods > name').each do |name|
        role_name = name.css('role roleTerm[@type="text"]').text

        unless ['Contributor', 'Creator'].include?(rolename)
          namePart = name.at_css('namePart')
          if namePart.text.end_with?("(#{role_name})")
            puts "Already migrated: #{namePart.text}"
            next
          end
          newName = "#{namePart.text} (#{role_name})"

          puts "Modifying #{newName}"
          modified = true

          namePart.content = newName
        end
      end

      if !modified
        puts "#{mo.id} No changes"
        return
      end

      mo.descMetadata.content = doc.to_xml

      if mo.descMetadata.save && mo.update_index
        puts "#{mo.id} Saved"
      else
        puts "ERROR: Unable to save #{mo.id}"
        puts "#{mo.errors}"
      end

    rescue => e
      puts "ERROR: #{e}"
      puts e.backtrace
    end
  end
end