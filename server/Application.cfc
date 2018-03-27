		component {
	this.name = "luceeDocumentationLocalServer-" & Hash( GetCurrentTemplatePath() );

	this.cwd     = GetDirectoryFromPath( GetCurrentTemplatePath() )
	this.baseDir = ExpandPath( this.cwd & "../" );

	this.mappings[ "/api"      ] = this.baseDir & "api";
	this.mappings[ "/builders" ] = this.baseDir & "builders";
	this.mappings[ "/docs"     ] = this.baseDir & "docs";

	public boolean function onRequest( required string requestedTemplate ) output=true {
		var path = _getRequestUri();
		if ( path eq "/assets/js/searchIndex.json" ) {
			_renderSearchIndex();
		} elseif ( path.startsWith( "/assets" ) ) {
			_renderAsset();
		} elseif ( path.startsWith( "/editor.html" ) ) {
			_renderCodeEditor();
		} elseif ( path.startsWith( "/source" ) ) {
			_renderSource();
		} else {
			_renderPage();
		}

		return true;
	}

// PRIVATE
	private void function _renderPage() {
		var pagePath    = _getPagePathFromRequest();
		var buildRunner = _getBuildRunner();
		var docTree     = buildRunner.getDocTree();
		var page        = docTree.getPageByPath( pagePath );

		if ( IsNull( page ) ) {
			_404();
		}

		WriteOutput( buildRunner.getBuilder( "html" ).renderPage( page, docTree, true ) );
	}

	private void function _renderSource() {
		var buildRunner = _getBuildRunner();
		var docTree     = buildRunner.getDocTree();
		var pagePath = Replace(_getRequestUri(), "/source", "");

		cflog(text="#cgi.request_method# _renderSource #pagePath#");
		var page = docTree.getPageSource(pagePath);
		content type="application/json";

		if (cgi.request_method eq "POST"){
			param name="form.content" default="";
			param name="form.properties" default="";
			var props = {};
			if (structCount(page.properties) and len(form.properties) eq 0){
				// page had properties
				header statuscode=422;
				WriteOutput("Properties missing");
				abort;
			} else if (isJson(form.properties)){
				props = deserializeJSON(form.properties);
				if (structCount(page.properties) gt 0 and structCount(props) eq 0){
					header statuscode=422 statustext="Properties missing";
					WriteOutput("Page previously had properties defined");
					abort;
				}
			}
			var result = docTree.updatePageSource(pagePath, form.content, props);
			WriteOutput( serializeJSON(result) );
		} else {
			var pageSource = structNew("linked");
			pageSource["file"] = pagePath;
			pageSource["content"] = page.content;
			pageSource["properties"] = page.properties;
			if (structCount(page.properties)){
				pageSource["reference"] = {
					"categories": docTree.getCategories(),
					"pages": docTree.getPageIds()
				};
				pageSource["propertyTypes"] = page.types;
			} else {
				structDelete(page, "properties");
			}

			WriteOutput( serializeJSON(pageSource) );
		}
	}

	private void function _renderAsset() {
		var assetPath = "/builders/html" & _getRequestUri();

		if ( !FileExists( assetPath ) ) {
			_404();
		}

		header name="cache-control" value="no-cache";
		content file=assetPath type=_getMimeTypeForAsset( assetPath );
		abort;
	}

	private void function _renderCodeEditor() {
		var editorPath = "/builders/html/assets/trycf/index.html";
		var content    = FileRead( editorPath );

		content reset=true;echo(content);abort;
	}

	private void function _renderSearchIndex() {
		var buildRunner = _getBuildRunner();
		var docTree = buildRunner.getDocTree();
		var searchIndex = buildRunner.getBuilder( "html" ).renderSearchIndex( docTree );

		header name="cache-control" value="no-cache";
		content type="application/json" reset=true;
		writeOutput( searchIndex );
		abort;
	}

	private string function _getPagePathFromRequest() {
		var path = _getRequestUri();

		path = ReReplace( path, "\.html$", "" );

		if ( path == "/" || path == "/index" ) {
			path = "/home";
		}

 		return path;
	}

	private string function _getRequestUri() {
		return request[ "javax.servlet.forward.request_uri" ] ?: "/";
	}

	private void function _404() {
		content reset="true" type="text/plain";
		header statuscode=404;
		abort;
	}

	private string function _getMimeTypeForAsset( required string filePath ) {
		var extension = ListLast( filePath, "." );

		switch( extension ){
			case "css": return "text/css";
			case "js" : return "application/javascript";
			case "jpe": case "jpeg": case "jpg": return "image/jpg";
			case "png": return "image/png";
			case "gif": return "image/gif";
			case "svg": return "image/svg+xml";
			case "woff": return "font/x-woff";
			case "eot": return "application/vnd.ms-fontobject";
			case "otf": return "font/otf";
			case "ttf": return "application/octet-stream";
		}

		return "application/octet-stream";
	}

	private any function _getBuildRunner() {
		var appKey    = application.buildRunnerKey ?: "";
		var newAppKey = _calculateBuildRunnerAppKey()

		if ( appKey != newAppKey || !application.keyExists( appKey ) ) {
			application.delete( appKey );
			application[ newAppKey ] = new api.build.BuildRunner();
			application.buildRunnerKey = newAppKey;
		}

		return application[ newAppKey ];

	}

	private string function _calculateBuildRunnerAppKey() {
		var filesEtc = DirectoryList( "/docs", true, "query" );
		var sig      = Hash( SerializeJson( filesEtc ) );

		return "buildrunner" & sig;
	}
}