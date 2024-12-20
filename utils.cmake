include_guard(DIRECTORY)

#find the full path to this utils.cmake file
include(utils RESULT_VARIABLE utils_file_path)
cmake_path(GET utils_file_path PARENT_PATH utils_file_dir)

#super searcher to get all target depencies of TOP_TARGET.
function(get_all_target_dependancies CUR_TARGET TOP_TARGET TARGET_LIST)

    get_target_property(cur_target_type ${CUR_TARGET} TYPE)
    #message("target ${CUR_TARGET} is of type ${cur_target_type}")
    
    if(${cur_target_type} STREQUAL "INTERFACE_LIBRARY")
        get_target_property(linkLibs ${CUR_TARGET} INTERFACE_LINK_LIBRARIES)
    else()
        get_target_property(linkLibs ${CUR_TARGET} LINK_LIBRARIES)
        
    endif()

    get_target_property(extrLinkLibs ${CUR_TARGET} EXTRA_TARGET_DEPENDANCIES)
    if( NOT ("${extrLinkLibs}" STREQUAL "extrLinkLibs-NOTFOUND"))
        list(APPEND linkLibs ${extrLinkLibs})
        #message("adding extrLinkLibs = ${extrLinkLibs} for ${CUR_TARGET}")
    endif()

    if(NOT(linkLibs STREQUAL "linkLibs-NOTFOUND"))
        #message("linkLibs is ${linkLibs}")
        foreach(lib IN LISTS linkLibs)
            #message("lib is ${lib}")


            list(FIND ${TARGET_LIST} ${lib} libAlreadyExists)

            if( (TARGET ${lib}) AND (${libAlreadyExists} EQUAL "-1"))

                #get real target
                get_target_property(realLib ${lib} ALIASED_TARGET)
                if(${realLib})
                    set(lib ${realLib})
                endif()

                list(APPEND ${TARGET_LIST} ${lib})

                get_all_target_dependancies(${lib} ${TOP_TARGET} ${TARGET_LIST})
            endif()
        endforeach()

    endif()

    list(REMOVE_DUPLICATES ${TARGET_LIST})
    set(${TARGET_LIST} ${${TARGET_LIST}} PARENT_SCOPE)

endfunction()










#super searcher to get full paths to all binary dependancy files paths of TOP_TARGET.  result paths are in BINARY_PATHS_LIST.
#if target is imported uses IMPORTED_LOCATION, otherwise if cmake defined target, uses BINARY_DIR
#
#on *NIX local SO_VERSION symbolic links are also included.
#
#set NO_GENEX to True avoid generator expressions in final BINARY_PATHS_LIST
function(get_all_binary_dependancy_files CUR_TARGET TOP_TARGET BINARY_PATHS_LIST)

    #message("CUR_TARGET is ${CUR_TARGET}")
    if (TARGET ${CUR_TARGET})
        get_target_property(cur_target_type ${CUR_TARGET} TYPE)
        #message("target ${CUR_TARGET} is of type ${cur_target_type}")
    
    else()
        return()
    endif()


    if(${cur_target_type} STREQUAL "INTERFACE_LIBRARY")
        get_target_property(linkLibs ${CUR_TARGET} INTERFACE_LINK_LIBRARIES)
    else()
        get_target_property(linkLibs ${CUR_TARGET} LINK_LIBRARIES)
        
    endif()

    get_target_property(extrLinkLibs ${CUR_TARGET} EXTRA_TARGET_DEPENDANCIES)
    if( NOT ("${extrLinkLibs}" STREQUAL "extrLinkLibs-NOTFOUND"))
        list(APPEND linkLibs ${extrLinkLibs})
        #message("adding extrLinkLibs = ${extrLinkLibs} for ${CUR_TARGET}")
    endif()

    #message("extrLinkLibs for ${CUR_TARGET} is: ${extrLinkLibs}")
    #message("linkLibs for ${CUR_TARGET} is: ${linkLibs}")

    if(NOT(linkLibs STREQUAL "linkLibs-NOTFOUND"))
        foreach(lib IN LISTS linkLibs)
            #message("lib is ${lib}")


            #conan puts interface link libraries in genex - do a specific conan extraction to get actual target
            #this seems the only path forward for getting configure time binary paths out of conan.
            string(REGEX MATCH "CONAN_LIB::+[^>]+" conanExtraction ${lib})
            if(conanExtraction)
                #message("conanExtraction is ${conanExtraction}")
                set(lib ${conanExtraction})

                get_target_property(subDeps ${lib} INTERFACE_LINK_LIBRARIES )
                #message("Conan subdeps of target ${lib} are ${subDeps}")

                #recurse
                foreach(subdep IN LISTS subDeps)
                    #message("recurse C")
                    get_all_binary_dependancy_files(${subdep} ${lib} ${BINARY_PATHS_LIST})
                endforeach()
            endif()
            

            if(TARGET ${lib})#TODO this fails of imported interface targets?

                #get real target
                get_target_property(realLib ${lib} ALIASED_TARGET)
                if(${realLib})
                    set(lib ${realLib})
                endif()

                get_target_property(target_type ${lib} TYPE)
                #message("target_type of ${lib} is ${target_type}")

                get_target_property(full_binary_dir ${lib} BINARY_DIR)
                set(full_binary_dir ${full_binary_dir}/${CMAKE_CFG_INTDIR})#TODO https://cmake.org/cmake/help/latest/variable/CMAKE_CFG_INTDIR.html

                #message("full_binary_dir is ${full_binary_dir}")

                get_target_property(name ${lib} NAME)
                #message("NAME for ${lib} is ${name}")

                #resolve lib file name
                get_target_property(lib_soversion ${lib} SOVERSION)
                get_target_property(lib_version ${lib} VERSION)
                #message("lib_soversion for ${lib} is ${lib_soversion}")
                #message("lib_version for ${lib} is ${lib_version}")


                #get_target_property(loc ${lib} LOCATION)
                #message("LOCATION for ${lib} is ${loc}")

                if(${CMAKE_BUILD_TYPE} MATCHES "Rel+")
                    get_target_property(imported_loc ${lib} IMPORTED_LOCATION)
                else()
                    get_target_property(imported_loc ${lib} IMPORTED_LOCATION_${CMAKE_BUILD_TYPE})
                endif()
                #message("imported_loc for ${lib} is ${imported_loc}")


                if((${target_type} STREQUAL "SHARED_LIBRARY") OR (${target_type} STREQUAL "MODULE_LIBRARY"))
                    get_target_property(imported_so_name ${lib} IMPORTED_SONAME)
                    if(NOT (${imported_so_name} STREQUAL "imported_so_name-NOTFOUND"))
                        #message("IMPORTED_SONAME for target: ${lib} is ${imported_so_name}")
                        if(imported_loc)
                            list(APPEND ${BINARY_PATHS_LIST} ${imported_loc})
                            #message("appending to list ${imported_loc}")

                            cmake_path(GET imported_loc STEM baseName)
                            cmake_path(GET imported_loc PARENT_PATH dir)

                        else()
                            list(APPEND ${BINARY_PATHS_LIST} ${full_binary_dir}/${imported_so_name})
                            #message("appending to list ${full_binary_dir}/${imported_so_name}")
                            cmake_path(GET imported_so_name STEM baseName)
                            set(dir ${full_binary_dir})

                        endif()

                        
                        

                        #gather symbolic links (TODO Gather this code)
                        if(${OS_MACOS})
                            if(lib_soversion)
                                list(APPEND ${BINARY_PATHS_LIST} ${dir}/${baseName}.${lib_soversion}.dylib) 
                                list(APPEND ${BINARY_PATHS_LIST} ${dir}/${baseName}.dylib) 
                            endif()
                        elseif(${OS_LINUX})
                            if(lib_soversion)
                                #message("adding symbolic link: ${dir}/${baseName}.so.${lib_soversion}")
                                list(APPEND ${BINARY_PATHS_LIST} ${dir}/${baseName}.so.${lib_soversion}) 
                                list(APPEND ${BINARY_PATHS_LIST} ${dir}/${baseName}.so) 
                            endif()
                        endif()
                        


                        set(${BINARY_PATHS_LIST} ${${BINARY_PATHS_LIST}} PARENT_SCOPE)
                        
                    else()
                        #message("target ${lib} has no imported soname")

                        if(${NO_GENEX})
                            #message("using no genex")
                            configtime_main_binary_file(${lib} libFilePath)
                            list(APPEND ${BINARY_PATHS_LIST} ${libFilePath})
                            cmake_path(GET libFilePath STEM baseName)
                            cmake_path(GET libFilePath PARENT_PATH dir)

                            #gather symbolic links (TODO Gather this code)
                            if(${OS_MACOS})
                                if(lib_soversion)
                                    list(APPEND ${BINARY_PATHS_LIST} ${dir}/${baseName}.${lib_soversion}.dylib) 
                                    list(APPEND ${BINARY_PATHS_LIST} ${dir}/${baseName}.dylib) 
                                endif()
                            elseif(${OS_LINUX})
                                if(lib_soversion)
                                    #message("adding symbolic link: ${dir}/${baseName}.so.${lib_soversion}")
                                    list(APPEND ${BINARY_PATHS_LIST} ${dir}/${baseName}.so.${lib_soversion}) 
                                    list(APPEND ${BINARY_PATHS_LIST} ${dir}/${baseName}.so) 
                                endif()
                            endif()

                        else()
                            #message("using genex")
                            list(APPEND ${BINARY_PATHS_LIST} $<TARGET_FILE:${lib}>)

                            #gather symbolic links (TODO Gather this code)
                            if(${OS_MACOS})
                                if(lib_soversion)
                                    list(APPEND ${BINARY_PATHS_LIST} ${full_binary_dir}/$<PATH:REMOVE_EXTENSION,$<TARGET_FILE_NAME:${lib}>>.${lib_soversion}.dylib) 
                                    list(APPEND ${BINARY_PATHS_LIST} ${full_binary_dir}/$<PATH:REMOVE_EXTENSION,$<TARGET_FILE_NAME:${lib}>>.dylib) 
                                endif()
                            elseif(${OS_LINUX})
                                if(lib_soversion)
                                    #message("adding symbolc links for lib ${lib}")
                                    list(APPEND ${BINARY_PATHS_LIST} ${full_binary_dir}/$<PATH:REMOVE_EXTENSION,$<TARGET_FILE_NAME:${lib}>>.so.${lib_soversion}) 
                                    list(APPEND ${BINARY_PATHS_LIST} ${full_binary_dir}/$<PATH:REMOVE_EXTENSION,$<TARGET_FILE_NAME:${lib}>>.so) 
                                endif()
                            endif()

                        endif()

                        if((${CMAKE_BUILD_TYPE} MATCHES "Deb+") AND (${OS_WINDOWS}))
                            if(${NO_GENEX})

                                configtime_main_pdb_file(${lib} libPDBFilePath)
                                list(APPEND ${BINARY_PATHS_LIST} ${libPDBFilePath}) 

                            else()
                                #This may not always resolve to a valid filename
                                list(APPEND ${BINARY_PATHS_LIST} ${full_binary_dir}/$<PATH:REMOVE_EXTENSION,$<TARGET_FILE_NAME:${lib}>>.pdb) 

                            endif()
                        endif()




                    endif()



                    #message("lib is shared: ${lib}")
                elseif((${target_type} STREQUAL "EXECUTABLE"))
                    #message("adding $<TARGET_FILE:${lib}> to bin paths list")
                    
                # elseif((${target_type} STREQUAL "MODULE_LIBRARY"))
                #     list(APPEND ${BINARY_PATHS_LIST} $<TARGET_FILE:${lib}>)

                elseif((${target_type} STREQUAL "INTERFACE_LIBRARY"))
                    #message("${lib} is an interface library")
                    get_target_property(subDeps ${lib} INTERFACE_LINK_LIBRARIES )
                    #message("INTERFACE_LINK_LIBRARIES of target ${lib} are ${subDeps}")
                    
                    #recurse
                    foreach(subdep IN LISTS subDeps)

                        #in some cases (conan) INTERFACE_LINK_LIBRARIES contains the lib itself - which would lead to recursion - so don't parse it.
                        set(SKIP FALSE)
                        if( "${subdep}" STREQUAL "${lib}" )
                            #message("FNVIUC")
                            set(SKIP TRUE)
                        endif()

                        if(NOT ${SKIP})
                            #message("recurse B")
                            get_all_binary_dependancy_files(${subdep} ${lib} ${BINARY_PATHS_LIST})
                        endif()
                    endforeach()


                elseif((${target_type} STREQUAL "UNKNOWN_LIBRARY"))
                    #no reliable extraction
                    #list(APPEND ${BINARY_PATHS_LIST} $<TARGET_FILE:${lib}>)
                endif()

                #also add files that are "attached" via the EXTRA_FILE_ATTACHEMENTS
                get_target_property(extra_file_attachments ${lib} EXTRA_FILE_ATTACHEMENTS)

                if( extra_file_attachments )
                    #message("adding extra attachments from lib - ${lib}: ${extra_file_attachments}")
                    list(APPEND ${BINARY_PATHS_LIST} "${extra_file_attachments}")
                    set(${BINARY_PATHS_LIST} ${${BINARY_PATHS_LIST}} PARENT_SCOPE)
                endif()


                get_target_property(extra_side_filename_attachments ${lib} EXTRA_SIDE_FILE_ATTACHEMENT_NAMES)
                #message("extra_side_filename_attachments for ${lib} is ${extra_side_filename_attachments}")
                if( extra_side_filename_attachments )
                    #message("EXTRA SIDE ATTACHEMENT!")
                    list(TRANSFORM extra_side_filename_attachments PREPEND "${full_binary_dir}/")
                
                    list(APPEND ${BINARY_PATHS_LIST} "${extra_side_filename_attachments}")
                    set(${BINARY_PATHS_LIST} ${${BINARY_PATHS_LIST}} PARENT_SCOPE)
                endif()

                #message("recurse A with lib ${lib}, CUR_TARGET is ${CUR_TARGET}")
                if(NOT (${lib} STREQUAL ${CUR_TARGET}))#avoid basic infinite recursion
                get_all_binary_dependancy_files(${lib} ${TOP_TARGET} ${BINARY_PATHS_LIST})
                endif()
            endif()
        endforeach()

    endif()

    list(REMOVE_DUPLICATES ${BINARY_PATHS_LIST})
    set(${BINARY_PATHS_LIST} ${${BINARY_PATHS_LIST}} PARENT_SCOPE)
    #message("function end")
endfunction()

function(string_contains_generator_exp STRING_VAR RESULT_BOOL)
    string(GENEX_STRIP "${STRING_VAR}" no_genex)

    if(STRING_VAR STREQUAL no_genex)
        # The string doesn't contain generator expressions.
        set(${RESULT_BOOL} FALSE PARENT_SCOPE)
    else()
        # The string contains generator expressions.
        set(${RESULT_BOOL} TRUE PARENT_SCOPE)
    endif()

endfunction()

#Add copies for binaries to build target TOP_TARGET
#if DEP_CHAIN_TARGET is specified - gathers dependancies from DEP_CHAIN_TARGET otherwise uses TOP_TARGET
#DESTINATION_VAR excepts generator expressions
function(add_binary_copy_commands TOP_TARGET DESTINATION_DIR)
    #set(BINARY_PATHS_LIST "")

    if(NOT ARGV2)
        set(DEP_CHAIN_TARGET ${TOP_TARGET})
    else()
        set(DEP_CHAIN_TARGET ${ARGV2})
    endif()
    #message("ARGV2 is ${ARGV2}")
    #message("DEP_CHAIN_TARGET is ${DEP_CHAIN_TARGET}")

    get_all_binary_dependancy_files(${DEP_CHAIN_TARGET} ${DEP_CHAIN_TARGET} list)
    #message("binary dependancy list for TOP_TARGET: ${TOP_TARGET} is ${list}")
    foreach(binaryPath ${list})
        #message("binaryPath is ${binaryPath}")
        string_contains_generator_exp(${binaryPath} hasGenEx)

        if(${hasGenEx})

            #wrap the path to change to end result is just the file name.
            set(pathOnly "$<PATH:REMOVE_FILENAME,${binaryPath}>")
            set(effectivefileonly $<PATH:RELATIVE_PATH,${binaryPath},${pathOnly}>)

            #https://gitlab.kitware.com/cmake/cmake/-/issues/14609
            add_custom_command(
                TARGET ${TOP_TARGET} PRE_LINK 
                COMMAND ${CMAKE_COMMAND} -P ${utils_file_dir}/simple_file_copy.cmake --
                ${binaryPath}
                ${DESTINATION_DIR}/${effectivefileonly}
                #COMMENT "Copy ${binaryPath} to ${DESTINATION_DIR}/${effectivefileonly}"
                )

        else()

            get_filename_component(binaryFileName ${binaryPath} NAME)

            #in magnum libs $(Configuration) is sometimes present https://github.com/mosra/magnum
            string(REPLACE "$(Configuration)" "${CMAKE_BUILD_TYPE}" binaryPath ${binaryPath})



            #https://gitlab.kitware.com/cmake/cmake/-/issues/14609
            add_custom_command(
                TARGET ${TOP_TARGET} PRE_LINK 
                COMMAND ${CMAKE_COMMAND} -P ${utils_file_dir}/simple_file_copy.cmake --
                ${binaryPath}
                ${DESTINATION_DIR}/${binaryFileName}
                #COMMENT "Copy ${binaryPath} to ${DESTINATION_DIR}/${binaryFileName}"
                )
            
            
        endif()


    endforeach()
endfunction()



function(configtime_executable_extension EXTSTR_VAR)
    if(${OS_WINDOWS})
        set(${EXTSTR_VAR} "exe" PARENT_SCOPE)
    else()
        set(${EXTSTR_VAR} "" PARENT_SCOPE)
    endif()
endfunction()

function(configtime_shared_library_extension EXTSTR_VAR)
    if(${OS_WINDOWS})
        set(${EXTSTR_VAR} "dll" PARENT_SCOPE)
    elseif(${OS_MACOS})
        set(${EXTSTR_VAR} "dylib" PARENT_SCOPE)
    elseif(${OS_LINUX})
        set(${EXTSTR_VAR} "so" PARENT_SCOPE)
    endif()
endfunction()

function(configtime_shared_library_prefix PRFXSTR_VAR)
    if(${OS_WINDOWS})
        set(${PRFXSTR_VAR} "" PARENT_SCOPE)
    elseif(${OS_MACOS})
        set(${PRFXSTR_VAR} "lib" PARENT_SCOPE)
    elseif(${OS_LINUX})
        set(${PRFXSTR_VAR} "lib" PARENT_SCOPE)
    endif()
endfunction()

function(configtime_shared_library_pdb_extension PDBSTR_VAR)
    if(${OS_WINDOWS})
        set(${PDBSTR_VAR} "pdb" PARENT_SCOPE)
    endif()
endfunction()

#-------------------------------------------------------------------------
function(configtime_static_library_extension EXTSTR_VAR)
    if(${OS_WINDOWS})
        set(${EXTSTR_VAR} "lib" PARENT_SCOPE)
    elseif(${OS_MACOS})
        set(${EXTSTR_VAR} "a" PARENT_SCOPE)
    elseif(${OS_LINUX})
        set(${EXTSTR_VAR} "a" PARENT_SCOPE)
    endif()
endfunction()

function(configtime_static_library_prefix EXTSTR_VAR)
    if(${OS_WINDOWS})
        set(${EXTSTR_VAR} "" PARENT_SCOPE)
    elseif(${OS_MACOS})
        set(${EXTSTR_VAR} "" PARENT_SCOPE)
    elseif(${OS_LINUX})
        set(${EXTSTR_VAR} "" PARENT_SCOPE)
    endif()
endfunction()


#Good Guess for executable filepath of target when generator expressions cannot be used.  Assumes CMAKE_BUILD_TYPE is Debug or Release
#for shared libs returns dll/dylib/so 
function(configtime_main_binary_file TARGET FILE_VAR)

    get_target_property(targetName ${TARGET} NAME)
    get_target_property(targetType ${TARGET} TYPE)
    get_target_property(targetFullBinaryDir ${TARGET} BINARY_DIR)
    set(targetFullBinaryDir ${targetFullBinaryDir}/${CMAKE_BUILD_TYPE})

    if( ${targetType}  STREQUAL  "SHARED_LIBRARY" )

        configtime_shared_library_extension(extstring)
        configtime_shared_library_prefix(prfxstring)
        set(${FILE_VAR} ${targetFullBinaryDir}/${prfxstring}${targetName}.${extstring} PARENT_SCOPE)

    elseif( ${targetType}  STREQUAL  "EXECUTABLE" )

        configtime_executable_extension(extstring)
        set(${FILE_VAR} ${targetFullBinaryDir}/${targetName}.${extstring} PARENT_SCOPE)

    endif()

endfunction()





#Good Guess for pdb filepath of target when generator expressions cannot be used.  Assumes CMAKE_BUILD_TYPE is Debug or Release
#for shared libs returns pdb
function(configtime_main_pdb_file TARGET FILE_VAR)

    get_target_property(targetName ${TARGET} NAME)
    get_target_property(targetType ${TARGET} TYPE)
    get_target_property(targetFullBinaryDir ${TARGET} BINARY_DIR)
    set(targetFullBinaryDir ${targetFullBinaryDir}/${CMAKE_BUILD_TYPE})

    if( ${targetType}  STREQUAL  "SHARED_LIBRARY" )

        configtime_shared_library_pdb_extension(extstring)
        configtime_shared_library_prefix(prfxstring)
        set(${FILE_VAR} ${targetFullBinaryDir}/${prfxstring}${targetName}.${extstring} PARENT_SCOPE)

    else()
        message(FATAL_ERROR "target not a shared library")
    endif()

endfunction()


#Good Guess for library filepath of target when generator expressions cannot be used.  Assumes CMAKE_BUILD_TYPE is Debug or Release
# returns .lib/.a etc
function(configtime_main_library_file TARGET FILE_VAR)

    get_target_property(targetName ${TARGET} NAME)
    get_target_property(targetType ${TARGET} TYPE)
    get_target_property(targetFullLibraryDir ${TARGET} BINARY_DIR)
    set(targetFullLibraryDir ${targetFullLibraryDir}/${CMAKE_BUILD_TYPE})

    if( ${targetType}  STREQUAL  "SHARED_LIBRARY" )

        #return the lib associated with dll on windows.  else dylib, so file
        if(${OS_WINDOWS})
            configtime_static_library_extension(extstring)
            configtime_static_library_prefix(prfxstring)
        else()
            configtime_shared_library_extension(extstring)
            configtime_shared_library_prefix(prfxstring)
        endif()
        set(${FILE_VAR} ${targetFullLibraryDir}/${prfxstring}${targetName}.${extstring} PARENT_SCOPE)

    elseif (${targetType} STREQUAL "STATIC_LIBRARY")

        configtime_static_library_extension(extstring)
        configtime_static_library_prefix(prfxstring)
        set(${FILE_VAR} ${targetFullLibraryDir}/${prfxstring}${targetName}.${extstring} PARENT_SCOPE)


    endif()

endfunction()


function(pad_string output str padchar length)
  string(LENGTH "${str}" _strlen)
  math(EXPR _strlen "${length} - ${_strlen}")

  if(_strlen GREATER 0)
    if(${CMAKE_VERSION} VERSION_LESS "3.14")
      unset(_pad)
      foreach(_i RANGE 1 ${_strlen}) # inclusive
        string(APPEND _pad ${padchar})
      endforeach()
    else()
      string(REPEAT ${padchar} ${_strlen} _pad)
    endif()
    string(APPEND str ${_pad})
  endif()

  set(${output} "${str}" PARENT_SCOPE)
endfunction()


function(make_dummy_executable_target TARGET_NAME_VAR)
    set(dummyContent "int main() {return 0\;}")
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/dummy_${TARGET_NAME_VAR}.cpp ${dummyContent})

    add_executable(${TARGET_NAME_VAR} ${CMAKE_CURRENT_BINARY_DIR}/dummy_${TARGET_NAME_VAR}.cpp)
endfunction()

function(make_dummy_static_lib_target TARGET_NAME_VAR)
    set(dummyContent "int func() {return 0\;}")
    file(WRITE ${CMAKE_CURRENT_BINARY_DIR}/dummy_${TARGET_NAME_VAR}.cpp ${dummyContent})

    add_library(${TARGET_NAME_VAR} STATIC ${CMAKE_CURRENT_BINARY_DIR}/dummy_${TARGET_NAME_VAR}.cpp)
endfunction()

#super function make a new static target that has custom commands attached to copy the dependancies of target_var
function(setup_dependancy_copy TARGET_VAR)

    make_dummy_static_lib_target(${TARGET_VAR}-hitchhiker)
    
    set_target_properties(${TARGET_VAR}-hitchhiker PROPERTIES FOLDER "Dependancy-Copy-Projects")
    
    target_link_libraries(${TARGET_VAR} PRIVATE ${TARGET_VAR}-hitchhiker)

    get_target_property(RuntimeOutputDir ${TARGET_VAR} RUNTIME_OUTPUT_DIRECTORY)
    get_target_property(LibraryOutputDir ${TARGET_VAR} LIBRARY_OUTPUT_DIRECTORY)
    get_target_property(ArchiveOutputDir ${TARGET_VAR} ARCHIVE_OUTPUT_DIRECTORY)
    get_target_property(binaryDir ${TARGET_VAR} BINARY_DIR)
    
    set_target_properties(${TARGET_VAR}-hitchhiker PROPERTIES RUNTIME_OUTPUT_DIRECTORY "${RuntimeOutputDir}")
    set_target_properties(${TARGET_VAR}-hitchhiker PROPERTIES LIBRARY_OUTPUT_DIRECTORY "${LibraryOutputDir}")
    set_target_properties(${TARGET_VAR}-hitchhiker PROPERTIES ARCHIVE_OUTPUT_DIRECTORY "${ArchiveOutputDir}")

    add_binary_copy_commands(${TARGET_VAR}-hitchhiker ${binaryDir} ${TARGET_VAR})
endfunction()






function(add_build_flag_printouts TARGET_NAME)

    add_custom_command(TARGET ${TARGET_NAME}  POST_BUILD
    COMMAND echo "target ${TARGET_NAME} built with CMake COMPILE_OPTIONS: \"$<TARGET_PROPERTY:${TARGET_NAME},COMPILE_OPTIONS>\"")

    add_custom_command(TARGET ${TARGET_NAME}  POST_BUILD
    COMMAND echo "target ${TARGET_NAME} built with CMake COMPILE_DEFINITIONS: \"$<TARGET_PROPERTY:${TARGET_NAME},COMPILE_DEFINITIONS>\"")

    add_custom_command(TARGET ${TARGET_NAME}  POST_BUILD
    COMMAND echo "target ${TARGET_NAME} built with CMake COMPILE_FEATURES: \"$<TARGET_PROPERTY:${TARGET_NAME},COMPILE_FEATURES>\"")

endfunction()



function(set_general_local_rpath_raw_files)

    set(options  )
    set(oneValueArgs  )
    set(multiValueArgs BINARY_FILE_LIST RELATIVE_PATHS_LIST)
    cmake_parse_arguments("set_general_local_rpath_raw_files" "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN} )


    foreach(binary ${set_general_local_rpath_raw_files_BINARY_FILE_LIST})
    #set rpaths to ONLY $ORIGIN
    if(${OS_LINUX})

            set(rPathString "")
            foreach(relPath ${set_general_local_rpath_raw_files_RELATIVE_PATHS_LIST})
                set(rPathString ${rPathString}:\$ORIGIN${relPath})
            endforeach()

            execute_process(
                COMMAND patchelf "--set-rpath" ${rPathString} "--debug" "${binary}"
                WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
                COMMAND_ECHO STDOUT
            )


    elseif( ${OS_MACOS} )


            #foreach(relPath ${RELATIVE_PATHS_LIST})
               
            execute_process(
                COMMAND install_name_tool "-add_rpath" "@loader_path/." "${binary}"
                WORKING_DIRECTORY ${FULL_BIN_DIR}
                COMMAND_ECHO STDOUT
            )

            #endforeach()

            
    endif()

    endforeach()

endfunction()


#add post build commands to set rpaths for executables and shared_libs
function(add_general_local_rpath_setup TARGET_NAME RELATIVE_PATHS_LIST)
    #set rpaths to ONLY $ORIGIN
    if(${OS_LINUX})

        if( ( ${TARGET_TYPE} STREQUAL "SHARED_LIBRARY" ) OR ( ${TARGET_TYPE} STREQUAL "EXECUTABLE") )

            set(rPathString "")
            foreach(relPath ${RELATIVE_PATHS_LIST})
                set(rPathString ${rPathString}:\$ORIGIN${relPath})
            endforeach()

            add_custom_command(
                TARGET ${TARGET_NAME} POST_BUILD
                COMMAND patchelf "--set-rpath" ${rPathString} "--debug" "$<TARGET_FILE:${TARGET_NAME}>"
                WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
                VERBATIM
            )
        endif()


    elseif( ${OS_MACOS} )



        if(( ${TARGET_TYPE} STREQUAL "EXECUTABLE") )

            foreach(relPath ${RELATIVE_PATHS_LIST})
                
                add_custom_command(
                    TARGET ${TARGET_NAME} POST_BUILD
                    COMMAND install_name_tool "-add_rpath" "@executable_path${relPath}/." "$<TARGET_FILE:${TARGET_NAME}>"
                    WORKING_DIRECTORY ${FULL_BIN_DIR}
                    COMMENT "Adding rpath \@executable_path${relPath}/. to $<TARGET_FILE:${TARGET_NAME}>"
                )
            
            endforeach()

        endif()
        
        
        if (( ${TARGET_TYPE} STREQUAL "SHARED_LIBRARY" ))

            add_custom_command(
                TARGET ${TARGET_NAME} POST_BUILD
                COMMAND install_name_tool "-add_rpath" "@loader_path/." "$<TARGET_FILE:${TARGET_NAME}>"
                WORKING_DIRECTORY ${FULL_BIN_DIR}
                COMMENT "Adding rpath \@loader_path/. to $<TARGET_FILE:${TARGET_NAME}>"
            )

            
            get_all_binary_dependancy_files(${TARGET_NAME} ${TARGET_NAME} list)
            
            foreach(binaryPath ${list})
                
                get_filename_component(fileName ${binaryPath} NAME)

                add_custom_command(
                    TARGET ${TARGET_NAME} POST_BUILD
                    COMMAND install_name_tool "-change" "${fileName}" "@rpath/${fileName}" "$<TARGET_FILE:${TARGET_NAME}>"
                    WORKING_DIRECTORY ${FULL_BIN_DIR}
                    COMMENT "changing LC_LOAD_DYLIB ${fileName} to @rpath/${fileName} for target $<TARGET_FILE:${TARGET_NAME}>"
                )

            endforeach()


        endif()

    endif()
endfunction()



#get the bin files from a conan package at config time.
function(get_conan_bin_files_config_time)
    set(options TARGET_NAMESPACE TARGET_NAME)
    set(oneValueArgs  )
    set(multiValueArgs CONAN_PACKAGE_NAME BINARIES_LIST)
    cmake_parse_arguments("arg_get_conan_bin_files_config_time" "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN} )

    set(buildTypeCaps ${CMAKE_BUILD_TYPE})
    string(TOUPPER ${buildTypeCaps} buildTypeCaps)
                        
    
    #set(fullPrefix "${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_${arg_get_conan_bin_files_config_time_TARGET_NAMESPACE}_${arg_get_conan_bin_files_config_time_TARGET_NAME}")
    set(fullPrefix "${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}")
    #append to prefix if more full name is specified
    if(arg_get_conan_bin_files_config_time_TARGET_NAMESPACE)
        set(fullPrefix "${fullPrefix}_${arg_get_conan_bin_files_config_time_TARGET_NAMESPACE}")
        if(arg_get_conan_bin_files_config_time_TARGET_NAME)
            set(fullPrefix "${fullPrefix}_${arg_get_conan_bin_files_config_time_TARGET_NAME}")
        endif()
    endif()

    #message("fullPrefix is ${fullPrefix}")

    if(OS_WINDOWS)
        #message("${fullPrefix}_BIN_DIRS_${buildTypeCaps} is ${${fullPrefix}_BIN_DIRS_${buildTypeCaps}}")
        file(GLOB_RECURSE ${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_dylibs "${${fullPrefix}_BIN_DIRS_${buildTypeCaps}}/*.dll")

        set(binariesList ${${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_dylibs})


    elseif(OS_LINUX)

        file(GLOB_RECURSE ${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_dylibs "${${fullPrefix}_LIB_DIRS_${buildTypeCaps}}/*.so")
        file(GLOB_RECURSE ${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_dylibs2 "${${fullPrefix}_LIB_DIRS_${buildTypeCaps}}/*.so.*")

        set(binariesList "${${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_dylibs};${${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_dylibs2}")

    elseif(OS_MACOS)

        file(GLOB_RECURSE ${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_dylibs "${${fullPrefix}_LIB_DIRS_${buildTypeCaps}}/*.dylib")

        set(binariesList ${${arg_get_conan_bin_files_config_time_CONAN_PACKAGE_NAME}_dylibs})

    endif()

    set(${arg_get_conan_bin_files_config_time_BINARIES_LIST} "${binariesList}" PARENT_SCOPE)

endfunction()





