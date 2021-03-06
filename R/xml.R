#' XML Node Schema
#'
#' Defines the XML schema of a node.
#'
#' @field schema_name the name of the schema
#' @field file_pattern regular expression pattern matching the file-name extension
#' @field extension the file-name extension
#' @field prefix the prefix that these documents have in the URI
#' @field atoms named character vector of xpath locations
#' @field constructor an RDF constructor function that can be called on
#'   a list of atoms extractor from a node in the schema
#' @field components a list of \code{XmlSchema} object containing the nested
#'   components in the node
#'
#'
#' @examples
#' taxonx = XmlSchema$new(schema_name = "taxonx", file_pattern = ".*\\.xml")
#'
#' @export
XmlSchema =
  R6::R6Class("xml_schema",
              public = list(
                schema_name = NULL,
                xpath = NA,
                file_pattern = NULL,
                extension = NULL,
                prefix = NULL,
                atoms = NULL,
                atom_types = NULL,
                atom_lang = NULL,
                constructor = NULL,
                injector = NULL,
                components = NULL,

                initialize =
                  function(schema_name = NA, xpath = NA, file_pattern = NA, extension = NA, prefix = NA, atoms = NA, atom_types = NULL, atom_lang = NA, constructor = NULL, injector = NULL, components = NULL)
                  {
                    self$schema_name = schema_name
                    self$xpath = xpath
                    self$file_pattern = file_pattern
                    self$extension = extension
                    self$prefix = prefix
                    self$atoms = atoms
                    self$atom_lang = atom_lang
                    self$atom_types = atom_types
                    self$constructor = constructor
                    self$injector = injector
                    self$components = components
                  }
              )
  )








#' RDF-ization of a Single XML File
#'
#' Converts an XML file to RDF and submits it to a triple store. Writes
#' the serialization in a file in the file system.
#'
#' @param filename locator, e.g. file path or URL, of the XML resource
#' @param xml_schema
#'        XML schema of the XML resource; one of
#'        taxpub taxonx or plazi_int
#' @param access_options endpoint to database to which to submit
#' @param serialization_dir directory where to dump intermediate serializations
#' @param serialization_format default is "turtle"
#' @param reprocess \code{logical}
#'
#' @return \code{logical}. TRUE if everything went OK. FALSE if there was a problem
#'
#'
#' @export
xml2rdf = function(filename, xml_schema = taxonx, access_options, serialization_dir, reprocess = FALSE, dry = FALSE)
{
  # generate lookup functions


  tryCatch(
    {
      xml = xml2::read_xml(filename)

      #xml_schema$injector(obkms_id = rdf4r::last_token(rdf4r::strip_filename_extension(filename), split = "/"), xml)

      triples = ResourceDescriptionFramework$new()
      root_id = identifier(
        root_id(xml, access_options, xml_schema),
        access_options$prefix["openbiodiv"]
      )

      triples$set_context(root_id)

      triples = node_extractor(
        node = xml,
        xml_schema = xml_schema,
        reprocess = reprocess,
        triples = triples,
        access_options = access_options,
        dry = dry,
        filename = filename
      )

      xml2::write_xml(xml, filename)

      serialization = triples$serialize()
     # add_data(serialization, access_options = access_options)

      cat(
        serialization,
        file = paste0(
          serialization_dir, "/",
          paste0(strip_filename_extension(last_token(filename, split = "/")), ".ttl")
        )
      )

      return(TRUE)
    },
    error = function(e)
    {
      warning(e)
      return(FALSE)
    })
}









#' Get the OBKMS Id of an XML node, if not set, set it.
#'
#' Does not do any database lookups.
#'
#' @param node the XML node from which to take the ID; cannot be missing!
#'
#' @return the local id (not an identifier object)
#'
#' @export
get_or_set_obkms_id = function (node)
{
  if (is.na(xml2::xml_attr(node, "obkms_id")))
  {
    xml2::xml_attr(node, "obkms_id") = uuid::UUIDgenerate()
  }

  xml2::xml_attr(node, "obkms_id")
}









#' Find (Re-)Processing Status
#'
#' @param node \code{XML2} object
#'
#' @return \code{logical} TRUE if the node has been processed, FALSE otherwise
#' @export
processing_status = function(node)
{
  if (is.na(xml2::xml_attr(node, "obkms_process"))) {
    return (FALSE)
  }
  else {
    return (as.logical(xml2::xml_attr(node, "obkms_process")))
  }
}









#' Finds the Atoms in a XML Node
#'
#' @param xml the XML node
#' @param xpath the atom locations as a named character vector
#' @param atom_types the type (explicitly stated, not as xpath) of the atom
#' @param atom_lang the language (as xpath), if the xpath fails, will set to
#'   en (if string)
#'
#' @return list
#'
#' @export
find_literals = function(xml, xml_schema)
{
  rr = vector(mode = 'list', length = length(xml_schema$atoms))
  names(rr) = names(xml_schema$atoms)
  for (nn in names(xml_schema$atoms))
  {
    #inside a particular name
    literals = xml2::xml_text(xml2::xml_find_all(xml, xml_schema$atoms[nn]))
    languages = tryCatch(
      xml2::xml_text(xml2::xml_find_all(xml, xml_schema$atom_lang[nn])),
      error = function(e) {
        NA
      }
    )

    rr[[nn]] = lapply(seq(along.with = literals), function(i)
    {
      literal(literals[i], xsd_type = xml_schema$atom_types[[nn]] ,lang = languages[i])
    }
    )
  }
  return(rr)
}




#'
#find_identifiers = function(node, xml_schema)
#{
#  lapply(xml_schmea$, function(p)
#  {
#    xml2::xml_text(xml2::xml_find_all(xml, p))
#  })
#
#}





#' Get the Parent OBKS Id for an XML Node
#'
#' Does not do any database lookups. Recursive looks for the parent node until
#' it finds one with ID.
#'
#' @param node the XML node from which to take the ID; cannot be missing!
#' @param fullname if TRUE, returns a URI with the OBKMS base prefix
#'
#' @export
parent_id = function (node, fullname = FALSE )
{
  obkms_id = NA
  path = xml2::xml_path( node )
  # will repeat while we don't have an id and we aren't at the top
  while ( path != "/" && is.na( obkms_id ) ) {
    node = xml2::xml_parent( node )
    obkms_id = xml2::xml_attr( node, "obkms_id")
    path = xml2::xml_path( node )
  }

  if ( fullname )
  {
    return (  paste0( strip_angle( obkms$prefixes$`_base`) , obkms_id ) )
  }

  else return ( obkms_id )
}















#' Get the Root (Article) OBKMS Id for an XML Node
#'
#' Does not do any database lookups - only looks at XML
#'
#' @param node
#'
#' @export
root_id = function(node, access_options, xml_schema = NULL)
{
  # Is the root id set?
  root_node = xml2::xml_find_all(node, xpath = "/*")

  if (is.na(xml2::xml_attr(root_node, "obkms_id"))) {
    ltitle <- literal(
      xml2::xml_text( xml2::xml_find_all(node, xml_schema$atoms["title"]))[1],
      xsd_type = rdf4r::xsd_string,
      lang = NA
    )

    opebiodiv_id_via_label_lookup = identifier_factory(
      fun = list(
        query_factory(
          p_query = qlookup_by_label,
          access_options = access_options
        )
      ),
      prefixes = access_options$prefix,
      def_prefix = access_options$prefix["openbiodiv"]
    )

    root_id = opebiodiv_id_via_label_lookup(list(ltitle))

    xml2::xml_attr(root_node, "obkms_id") = root_id$id
  }

  xml2::xml_attr(root_node, "obkms_id")
}

















#' Strips all XML tags
#'
#' @param xmldoc
#'
#' @return a vector of the document as plain text
#' @export
remove_all_tags = function(xmldoc) {
  sapply(xml_find_all(xmldoc, xpath = paste0("//", "p")), function(p) {
    xml_text(p) = paste(xml_text(p), "\n")
  })
  unescape_html(do.call(pasteconstr(" "), xml_find_all(xmldoc, "//text()")))
}

#' Unescpae HTML Characters
#'
#' @param str input string
#' @return string without the escape characters
#' @export
unescape_html <- function(str){
  xml2::xml_text(xml2::read_html(paste0("<x>", str, "</x>"

                                        )))
}





#' Simpler version of find literals
#'
#' Finds the Atoms in a XML Node
#'
#' @param xml the XML node
#' @param xpath the atom locations as a named character vector
#'
#' @return list
#'
#' @export
find_atoms =
  function(xml, xpath) {
    lapply(xpath, function(p)
    {
      xml2::xml_text(xml2::xml_find_all(xml, p))
    })
  }




#' Standard injector. Sets the id from the XPATH
#'
#' @param obkms_id
#' @param xml_node
#'
#' @return
#' @export
standard_injector = function(obkms_id, xml_node)
{
  xml2::xml_attr(xml_node, "obkms_id") = obkms_id
}

