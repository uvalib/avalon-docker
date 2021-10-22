namespace :uva do
  namespace :migrate do
    desc "Convert custom mods fields"
    task :all_mods => :environment do

      MediaObject.find_each({},{batch_size:5}) do |mo|
        doc = mo.descMetadata.ng_xml

        # output doc to file

        doc = convert_custom_name_roles(doc, mo)

        mo.descMetadata.content = doc.to_xml
        mo.descMetadata.save

        # output final doc
      end
    end

    def convert_custom_name_roles(doc, mo)
      doc.css('//name').each do |name|
        role_name = name.css('role roleTerm[@type="text"]').text

        unless ['Contributor', 'Creator'].include?(rolename)
          namePart = name.css('namePart')
          namePart.content = "#{namePart.text} (#{role_name})"
        end
      end
      return doc
    end
  end
end