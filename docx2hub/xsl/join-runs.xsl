<?xml version="1.0" encoding="UTF-8"?>
<xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform"
  xmlns:fn="http://www.w3.org/2005/xpath-functions"
  xmlns:xs="http://www.w3.org/2001/XMLSchema"
  xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
  xmlns:word200x="http://schemas.microsoft.com/office/word/2003/wordml"
  xmlns:v="urn:schemas-microsoft-com:vml" 
  xmlns:dbk="http://docbook.org/ns/docbook"
  xmlns:wx="http://schemas.microsoft.com/office/word/2003/auxHint"
  xmlns:o="urn:schemas-microsoft-com:office:office"
  xmlns:pkg="http://schemas.microsoft.com/office/2006/xmlPackage"
  xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
  xmlns:rel="http://schemas.openxmlformats.org/package/2006/relationships"
  xmlns:exsl='http://exslt.org/common'
  xmlns:saxon="http://saxon.sf.net/"
  xmlns:tr="http://transpect.io"
  xmlns:docx2hub="http://transpect.io/docx2hub"
  xmlns:mml="http://www.w3.org/1998/Math/MathML"
  xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math"
  xmlns:css="http://www.w3.org/1996/css"
  xmlns:calstable="http://docs.oasis-open.org/ns/oasis-exchange/table"
  xmlns="http://docbook.org/ns/docbook"
  version="2.0"
  exclude-result-prefixes = "w o v wx xs dbk pkg r rel word200x exsl saxon fn tr mml docx2hub calstable">

  <!--<xsl:import href="http://transpect.io/xslt-util/hex/xsl/hex.xsl"/>-->
  <xsl:import href="http://transpect.io/xslt-util/calstable/xsl/functions.xsl"/>
  
  <xsl:param name="terminate-on-unbalanced-instrTexts" select="'yes'" as="xs:string*"/>
  <xsl:param name="mml-version" as="xs:string?"/>
  <xsl:param name="normalize-thead" select="'yes'"/>
  
  <xsl:template match="/*" mode="docx2hub:join-runs" priority="-0.2">
    <!-- no copy-namespaces="no" in order to suppress excessive namespace declarations on every element -->
    <xsl:copy>
      <xsl:apply-templates select="@*, node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:variable name="footnote-ids" select="//dbk:footnote[not(@role='endnote')]/@xml:id" as="xs:string*"/>

  <xsl:variable name="endnote-ids" select="//dbk:footnote[@role='endnote']/@xml:id" as="xs:string*"/>
  
  <xsl:template match="docx2hub:citavi-jsons" mode="docx2hub:join-runs"/>

  <xsl:template match="dbk:bibliography[@role = 'Citavi']//comment()" mode="docx2hub:join-runs"/>

  <xsl:template match="dbk:biblioref[every $n in node() satisfies $n[matches(., '^\p{Zs}+$')]]" mode="docx2hub:join-runs">
    <xsl:value-of select="comment()"/>
  </xsl:template>

  <xsl:template match="dbk:para[
                         dbk:br[@role eq 'column'][preceding-sibling::node() and following-sibling::node()]
                       ]" mode="docx2hub:join-runs" priority="5">
    <xsl:variable name="context" select="." as="element(dbk:para)"/>
    <xsl:if test="@docx2hub:removable">
      <xsl:message terminate="yes">SHRIEK <xsl:sequence select="."/></xsl:message>
    </xsl:if>
    <xsl:variable name="split" as="element(dbk:para)+">
      <xsl:for-each-group select="node()" group-starting-with="dbk:br[@role eq 'column']">
        <para>
          <xsl:sequence select="$context/@*"/>
          <xsl:if test="$context/@srcpath and position() != 1 and $context/@srcpath">
            <xsl:attribute name="srcpath" select="concat($context/@srcpath, ';n=', position())"/>
          </xsl:if>
          <xsl:sequence select="current-group()[not(self::dbk:br[@role eq 'column'])]"/>
        </para>
      </xsl:for-each-group>
    </xsl:variable>
    <xsl:apply-templates select="$split" mode="#current"/>
  </xsl:template>

  <!-- w:r is here for historic reasons. We used to group the text runs
       prematurely until we found out that it is better to group when
       there's docbook markup. So we implemented the special case of
       dbk:anchors (corresponds to w:bookmarkStart/End) only for dbk:anchor. 
       dbk:anchors between identically formatted phrases will be merged
       with the phrases' content into a consolidated phrase. -->
  <xsl:template match="*[not(self::dbk:phrase[@role = 'docx2hub:EQ'])]
                        [not(ancestor::dbk:bibliography)]
                        [w:r or dbk:phrase or dbk:superscript or dbk:subscript]" 
                mode="docx2hub:join-runs" priority="3">
    <!-- move sidebars to para level -->
    <xsl:variable name="context" select="."/>
    <xsl:if test="self::dbk:para and .//dbk:sidebar">
      <xsl:call-template name="docx2hub_move-invalid-sidebar-elements"/>
    </xsl:if>
    <xsl:variable name="prelim" as="node()*">
      <xsl:variable name="processed-pagebreak-elements" as="item()*">
        <xsl:call-template name="docx2hub:pagebreak-elements-to-attributes"/>  
      </xsl:variable>
      <xsl:sequence select="$processed-pagebreak-elements/self::attribute(), $processed-pagebreak-elements/self::dbk:anchor"/>
      <xsl:for-each-group select="node()" group-adjacent="tr:signature(.)">
        <xsl:choose>
          <xsl:when test="current-grouping-key() = ('', 'phrase')">
            <xsl:apply-templates select="current-group()" mode="#current"/>
          </xsl:when>
          <xsl:when test="current-grouping-key() eq 'phrase___role__=__docx2hub:EQ'">
            <xsl:apply-templates select="current-group()" mode="#current"/>
          </xsl:when>
          <xsl:when test="starts-with(fn:current-grouping-key(), 'phrase')
                          and
                          current-group()/*[docx2hub:is-display-equation(.)]">
            <!-- https://github.com/transpect/docx2hub/issues/23 -->
            <xsl:apply-templates select="current-group()/*" mode="#current"/>
          </xsl:when>
          <!-- https://redmine.le-tex.de/issues/10523
               remove phrases that contain only a mediaobject -->
          <xsl:when test="count(current-group()) = 1
                          and current-group()/local-name() = 'phrase'
                          and current-group()[not(normalize-space())]
                          and current-group()[every $att in @*
                                              satisfies not(matches($att/local-name(), '^(role|border|background|color|display|position|top|left)'))]
                          and current-group()/count(*) = 1
                          and current-group()/*/local-name() = 'mediaobject'">
            <xsl:apply-templates select="current-group()/*" mode="#current"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:copy copy-namespaces="no">
              <xsl:apply-templates select="@role, @* except (@srcpath, @role)" mode="#current"/>
              <xsl:if test="self::dbk:phrase[@role='hub:identifier'] and ancestor-or-self::dbk:footnote[@xreflabel]">
                <xsl:apply-templates select="ancestor-or-self::dbk:footnote/@xreflabel" mode="#current"/>
              </xsl:if>
              <xsl:if test="$srcpaths = 'yes' and current-group()/@srcpath">
                <xsl:attribute name="srcpath" select="current-group()/@srcpath" separator=" "/>
              </xsl:if>
              <xsl:apply-templates select="current-group()[not(self::dbk:anchor)]/node() 
                                           union current-group()[self::dbk:anchor]" mode="#current" />
            </xsl:copy>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each-group>
      <xsl:sequence select="$processed-pagebreak-elements/self::dbk:anchors-to-the-end/dbk:anchor"/>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="self::dbk:phrase[empty(@*)]">
        <xsl:sequence select="$prelim"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:copy copy-namespaces="no">
          <xsl:apply-templates select="@*" mode="#current"/>
          <xsl:sequence select="$prelim"/>
        </xsl:copy>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="dbk:indexterm/*[dbk:phrase]
                                      [every $node in (* | text()[normalize-space()]) 
                                       satisfies (exists($node/self::dbk:phrase))]
                                      [count(distinct-values(for $phr in dbk:phrase return tr:signature($phr))) = 1]" 
                mode="docx2hub:join-runs_" priority="3">
    <!-- In order to retain the same results as before https://github.com/transpect/docx2hub/issues/26,
         we unwrap newly created phrases in indexterms and put the role attribute on primary etc. -->
    <!-- Update: We decided to disable this template, leaving phrases intact that cover the entire contents of
         primary etc. One reason was that it is easier to map to BITS: The term element doesn’t allow a content-type
         attribute, but it allows styled-content. -->
    <xsl:copy>
      <xsl:apply-templates select="@*, dbk:phrase[1]/(@* except @srcpath), 
                                  (dbk:phrase/node() | text()[not(normalize-space())] | comment() | processing-instruction())" 
                mode="#current"/>
    </xsl:copy>
  </xsl:template>

  <!-- changes in this commit: because of vr_SB_525-12345_NESTOR-Testdaten-01 ($most-frequent-lang) -->
  <xsl:template match="dbk:phrase[empty(@* except @srcpath)]" mode="docx2hub:join-runs" priority="2">
    <xsl:apply-templates mode="#current"/>
  </xsl:template>
  
  <!-- this is for the aforementioned file, in order to eliminate redundant @xml:lang on footnote paras
    with the same @xml:lang as their containing para -->
  <xsl:template match="dbk:para[empty(@role)][@xml:lang = ancestor::*[@xml:lang][1]/self::dbk:para[empty(@role)]/@xml:lang]/@xml:lang" 
    mode="docx2hub:join-runs"/>
  
  <xsl:template match="*" mode="docx2hub:join-runs">
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@role, @* except @role, node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="dbk:footnote[@xreflabel][descendant::dbk:phrase[@role='hub:identifier']]" mode="docx2hub:join-runs">
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@* except @xreflabel | node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="dbk:footnote/@xml:id" mode="docx2hub:join-runs">
      <xsl:attribute name="{name()}" select="concat('fn-', index-of($footnote-ids, .))"/>
  </xsl:template>
  
  <xsl:template match="dbk:footnote[@role='endnote']/@xml:id" mode="docx2hub:join-runs">
      <xsl:attribute name="{name()}" select="concat('en-', index-of($endnote-ids, .))"/>
  </xsl:template>

  <xsl:template match="dbk:phrase[@role='hub:identifier'][ancestor::dbk:footnote[@xreflabel]]" mode="docx2hub:join-runs" priority="+10">
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@* | ancestor::dbk:footnote/@xreflabel | node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>

  <!-- collateral: remove links that don’t link -->
  <xsl:template match="dbk:link[@*][every $a in @* satisfies ('srcpath' = $a/name())]" mode="docx2hub:join-runs" priority="5">
    <xsl:apply-templates mode="#current"/>
  </xsl:template>

  <xsl:key name="docx2hub:linking-item-by-id" match="*[@linkend | @linkends]" use="@linkend, tokenize(@linkends, '\s+')"/>
  <xsl:key name="docx2hub:item-by-id" match="*[@xml:id]" use="@xml:id"/>

  <!-- Postprocess EQ field functions -->
  <xsl:template match="dbk:phrase[@role = 'docx2hub:EQ']" mode="docx2hub:join-runs" priority="10">
    <xsl:variable name="next-match" as="node()*">
      <xsl:next-match/>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="exists(ancestor::dbk:phrase[@role = ('docx2hub:EQ', 'docx2hub:EQ_tmp')])">
        <xsl:sequence select="$next-match"/>
      </xsl:when>
      <xsl:when test="$next-match/self::dbk:phrase[@role = ('docx2hub:EQ', 'docx2hub:EQ_tmp')] and empty($next-match/node())">
        <!-- totally empty equations like EQ \O{} can be removed -->
      </xsl:when>
      <xsl:when test="$next-match/self::dbk:phrase[@role = ('docx2hub:EQ_tmp')]">
        <inlineequation role="EQ">
          <mml:math>
            <xsl:sequence select="$next-match/node()"/>
          </mml:math>
        </inlineequation>
      </xsl:when>
      <xsl:otherwise>
        <inlineequation role="EQ">
          <mml:math>
            <xsl:sequence select="$next-match"/>
          </mml:math>
        </inlineequation>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template name="docx2hub:EQ-mrow">
    <xsl:param name="nodes" as="node()*"/>
    <xsl:variable name="prelim" as="node()*">
      <xsl:apply-templates select="$nodes" mode="#current"/>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="count($prelim/self::*) = 1">
        <xsl:sequence select="$prelim"/>
      </xsl:when>
      <xsl:otherwise>
        <mml:mrow>
          <xsl:sequence select="$prelim"/>
        </mml:mrow>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:template match="dbk:phrase[@role = 'docx2hub:EQ']" mode="docx2hub:join-runs">
    <xsl:call-template name="nest-eq">
      <xsl:with-param name="nodes" select="node()"/>
      <xsl:with-param name="level" select="1"/>
    </xsl:call-template>
  </xsl:template>
  
  <xsl:template name="nest-eq">
    <xsl:param name="nodes" as="node()*"/>
    <xsl:param name="level" as="xs:integer"/>
    <xsl:variable name="first-open" select="($nodes/self::dbk:open-delim)[1]" as="element(dbk:open-delim)?"/>
    <xsl:variable name="last-close" select="($nodes/self::dbk:close-delim)[last()]" as="element(dbk:close-delim)?"/>
    <xsl:variable name="prelim" as="element(dbk:phrase)">
      <phrase role="docx2hub:EQ_tmp">
        <xsl:for-each-group select="$nodes"
          group-starting-with="dbk:open-delim[(following-sibling::dbk:open-delim  
                                               | following-sibling::dbk:close-delim)[1]/self::dbk:close-delim]">
          <xsl:variable name="open" as="element(dbk:open-delim)?" select="self::dbk:open-delim"/>
          <xsl:variable name="close" as="element(dbk:close-delim)?" select="(current-group()/self::dbk:close-delim)[1]"/>
          <xsl:choose>
            <xsl:when test="exists($open) and exists($close)">
              <paren-group>
                <xsl:sequence select="current-group()[. &lt;&lt; $close] except $open"/>
              </paren-group>
              <xsl:sequence select="current-group()[. >> $close]"/>
            </xsl:when>
            <xsl:otherwise>
              <xsl:sequence select="current-group()"/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each-group>    
      </phrase>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="exists($prelim/dbk:open-delim)">
        <xsl:call-template name="nest-eq">
          <xsl:with-param name="nodes" select="$prelim/node()"/>
          <xsl:with-param name="level" select="$level + 1"/>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <xsl:apply-templates select="$prelim" mode="#current"/>
<!--     debug:   <xsl:sequence select="$prelim"/>-->
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>

  <xsl:function name="docx2hub:preceding-eq-macro" as="element(*)?">
    <xsl:param name="context" as="element(dbk:paren-group)"/>
    <xsl:sequence select="$context/preceding-sibling::node()[empty(self::text()[not(normalize-space())])][1]
                            /(self::dbk:frac | self::dbk:root | self::dbk:fenced 
                              | self::dbk:overline | self::dbk:over | self::dbk:sub | self::dbk:sup)"/>
  </xsl:function>

  <xsl:template match="dbk:frac | dbk:root | dbk:fenced | dbk:overline | dbk:over | dbk:sub | dbk:sup" mode="docx2hub:join-runs"/>

  <xsl:template match="dbk:paren-group[docx2hub:preceding-eq-macro(.)/self::dbk:frac]" mode="docx2hub:join-runs" priority="5">
    <xsl:variable name="sep" as="element(dbk:sep)?" select="dbk:sep"/>
    <xsl:if test="empty($sep)">
      <xsl:message select="'Empty $sep: ', ."/>
    </xsl:if>
    <mml:mfrac>
      <xsl:call-template name="docx2hub:EQ-mrow">
        <xsl:with-param name="nodes" select="node()[. &lt;&lt; $sep]"/>
      </xsl:call-template>
      <xsl:call-template name="docx2hub:EQ-mrow">
        <xsl:with-param name="nodes" select="node()[. >> $sep]"/>
      </xsl:call-template>
    </mml:mfrac>
  </xsl:template>

  <xsl:template match="dbk:paren-group[docx2hub:preceding-eq-macro(.)/self::dbk:root]" mode="docx2hub:join-runs" priority="5">
    <xsl:variable name="sep" as="element(dbk:sep)?" select="dbk:sep"/>
    <xsl:choose>
      <xsl:when test="exists(node()[following-sibling::dbk:sep])">
        <mml:mroot>
          <xsl:call-template name="docx2hub:EQ-mrow">
            <xsl:with-param name="nodes" select="node()[preceding-sibling::dbk:sep]"/>
          </xsl:call-template>
          <xsl:call-template name="docx2hub:EQ-mrow">
            <xsl:with-param name="nodes" select="node()[following-sibling::dbk:sep]"/>
          </xsl:call-template>
        </mml:mroot>
      </xsl:when>
      <xsl:otherwise>
        <mml:msqrt>
          <xsl:call-template name="docx2hub:EQ-mrow">
            <xsl:with-param name="nodes" select="node() except dbk:sep"/>
          </xsl:call-template>
        </mml:msqrt>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="dbk:paren-group[docx2hub:preceding-eq-macro(.)/self::dbk:overline]" mode="docx2hub:join-runs" priority="5">
    <mml:mover accent="true">
      <xsl:call-template name="docx2hub:EQ-mrow">
        <xsl:with-param name="nodes" select="node()"/>
      </xsl:call-template>
      <mml:mo stretchy="true">&#xAF;<!-- macron --></mml:mo>
    </mml:mover>
  </xsl:template>
  
  <xsl:template match="dbk:paren-group[docx2hub:preceding-eq-macro(.)/self::dbk:over]" mode="docx2hub:join-runs" priority="5">
    <xsl:if test="count(dbk:sep) gt 1">
      <xsl:message terminate="yes">docx2hub:join-runs: Implement more than one stacked item in <xsl:sequence select=".."/></xsl:message>
    </xsl:if>
    <mml:mover>
      <xsl:call-template name="docx2hub:EQ-mrow">
        <xsl:with-param name="nodes" select="node()[following-sibling::dbk:sep]"/>
      </xsl:call-template>
      <xsl:call-template name="docx2hub:EQ-mrow">
        <xsl:with-param name="nodes" select="node()[preceding-sibling::dbk:sep]"/>
      </xsl:call-template>
    </mml:mover>
  </xsl:template>
  
  <xsl:template match="dbk:paren-group[docx2hub:preceding-eq-macro(.)/self::dbk:sup]" mode="docx2hub:join-runs" priority="5">
    <mml:msup>
      <mml:mrow/>
      <xsl:call-template name="docx2hub:EQ-mrow">
        <xsl:with-param name="nodes" select="node()"/>
      </xsl:call-template>
    </mml:msup>
  </xsl:template>
  
  <xsl:template match="dbk:paren-group[docx2hub:preceding-eq-macro(.)/self::dbk:sub]" mode="docx2hub:join-runs" priority="5">
    <mml:msub>
      <mml:mrow/>
      <xsl:call-template name="docx2hub:EQ-mrow">
        <xsl:with-param name="nodes" select="node()"/>
      </xsl:call-template>
    </mml:msub>
  </xsl:template>
  
  <xsl:template match="dbk:paren-group[docx2hub:preceding-eq-macro(.)/self::dbk:fenced]" mode="docx2hub:join-runs" priority="5">
    <xsl:variable name="fenced" as="element(dbk:fenced)" select="docx2hub:preceding-eq-macro(.)"/>
    <mml:mrow>
      <mml:mo>
        <xsl:value-of select="($fenced/@open, '(')[1]"/>
      </mml:mo>
      <xsl:call-template name="docx2hub:EQ-mrow">
        <xsl:with-param name="nodes" select="node()"/>
      </xsl:call-template>
      <mml:mo>
        <xsl:value-of select="($fenced/@close, ')')[1]"/>
      </mml:mo>
    </mml:mrow>
  </xsl:template>
  
  <xsl:template match="dbk:paren-group" mode="docx2hub:join-runs">
    <mml:mo>(</mml:mo>
    <xsl:call-template name="docx2hub:EQ-mrow">
      <xsl:with-param name="nodes" select="node()"/>
    </xsl:call-template>
    <mml:mo>)</mml:mo>
  </xsl:template>
  
  <xsl:template match="dbk:phrase[@role = ('docx2hub:EQ', 'docx2hub:EQ_tmp')]//text()" mode="docx2hub:join-runs">
    <xsl:variable name="prelim" as="document-node()">
      <xsl:document>
        <xsl:analyze-string select="." flags="x"
          regex="({$docx2hub:functions-names-regex}|
                  kg|mg|mmol|
                  \p{{L}}|[\d,.]+|\p{{S}}|\p{{P}}|-|\s+)">
          <xsl:matching-substring>
            <xsl:choose>
              <xsl:when test="matches(., '^\p{L}{2,}$')">
                <mml:mi>
                  <xsl:value-of select="."/>
                </mml:mi>
              </xsl:when>
              <xsl:when test="matches(., '[\d,.]+')">
                <mml:mn>
                  <xsl:value-of select="."/>
                </mml:mn>
              </xsl:when>
              <xsl:when test="matches(., '\s+')">
                <mml:mspace width="{string-length(.) * 0.25}em"/>
              </xsl:when>
              <xsl:when test=". = '-'">
                <mml:mo>
                  <xsl:value-of select="'&#x2212;'"/>
                </mml:mo>
              </xsl:when>
              <xsl:when test="matches(., '[\p{S}\p{P}]')">
                <mml:mo>
                  <xsl:value-of select="."/>
                </mml:mo>
              </xsl:when>
              <xsl:when test="matches(., '\p{L}')">
                <mml:mi>
                  <xsl:value-of select="."/>
                </mml:mi>
              </xsl:when>
              <xsl:otherwise>
                <mml:mtext>
                  <xsl:value-of select="."/>
                </mml:mtext>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:matching-substring>
        </xsl:analyze-string>
      </xsl:document>
    </xsl:variable>
    <xsl:sequence select="$prelim/(* except mml:mspace[following-sibling::*[1]/self::mml:mo
                                                       | preceding-sibling::*[1]/self::mml:mo])"/>
  </xsl:template>

  <!-- copied and renamed from https://github.com/transpect/mml2tex/trunk/xsl/function-names.xsl -->
  <xsl:variable name="docx2hub:function-names" as="xs:string+" 
                select="('arccos',
                         'arcsin',
                         'arctan',
                         'arg',
                         'cos',
                         'cosh',
                         'cot',
                         'coth',
                         'csc',
                         'deg',
                         'det',
                         'dim',
                         'exp',
                         'gcd',
                         'hom',
                         'inf',
                         'ker', 
                         'lg',
                         'lim', 
                         'liminf', 
                         'limsup', 
                         'ln', 
                         'log', 
                         'max', 
                         'min', 
                         'Pr', 
                         'sec', 
                         'sin',
                         'sinh', 
                         'sup', 
                         'tan', 
                         'tanh'
                         )"/>
  
  <xsl:variable name="docx2hub:functions-names-regex" select="concat('(', string-join($docx2hub:function-names, '|'), ')')" as="xs:string"/>


  <!-- collateral: deflate an adjacent start/end anchor pair to a single anchor --> 
  <xsl:template match="dbk:anchor[
                         following-sibling::node()[1] is (key('docx2hub:linking-item-by-id', @xml:id)/self::dbk:anchor)[1]
                       ]" mode="docx2hub:join-runs">
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@* except @role" mode="#current"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="dbk:anchor[
                         preceding-sibling::node()[1] is (key('docx2hub:item-by-id', @linkend))[1]
                       ]" mode="docx2hub:join-runs"/>

  <xsl:template match="dbk:anchor/@linkend" mode="docx2hub:join-runs">
    <!-- I’d like to keep it for bookmark ranges, but it isn’t allowed in DocBook -->
  </xsl:template>

  <!-- collateral: create indexterms for what was a bookmark range in docx -->
  <xsl:template match="dbk:anchor[exists(key('docx2hub:linking-item-by-id', @xml:id)/self::dbk:indexterm[@linkends])]"
    mode="docx2hub:join-runs" priority="1">
    <xsl:variable name="next-match" as="element(dbk:anchor)?">
      <xsl:next-match/>  
    </xsl:variable>
    <xsl:sequence select="$next-match"/>
    <xsl:variable name="indexterms" as="element(dbk:indexterm)+" 
      select="key('docx2hub:linking-item-by-id', @xml:id)/self::dbk:indexterm"/>
    <xsl:variable name="context" select="." as="element(dbk:anchor)"/>
    <xsl:for-each select="$indexterms">
      <xsl:variable name="pos" as="xs:integer" select="index-of(tokenize(@linkends, '\s+'), $context/@xml:id)"/>
      <xsl:variable name="id" select="concat('itr_', generate-id())" as="xs:string"/>
      <xsl:choose>
        <xsl:when test="$pos = 1">
          <xsl:copy copy-namespaces="no">
            <xsl:apply-templates select="@* except @linkends" mode="#current"/>
            <xsl:if test="$next-match/@role = ('start', 'hub:start')">
              <xsl:attribute name="xml:id" select="$id"/>
              <xsl:attribute name="class" select="'startofrange'"/>
            </xsl:if>
            <xsl:apply-templates mode="#current"/>
          </xsl:copy>
        </xsl:when>
        <xsl:when test="$pos = 2 and exists($next-match)">
          <xsl:copy copy-namespaces="no">
            <xsl:apply-templates select="@* except @linkends" mode="#current"/>
            <xsl:attribute name="startref" select="$id"/>
            <xsl:attribute name="class" select="'endofrange'"/>
          </xsl:copy>
        </xsl:when>
      </xsl:choose>
    </xsl:for-each>
  </xsl:template>

  <xsl:template match="dbk:indexterm[@linkends]" mode="docx2hub:join-runs"/>

  <!-- collateral: replace name of mapped symbols with default Unicode font name -->
  <xsl:template match="@css:font-family[. = $docx2hub:symbol-font-names][.. = docx2hub:font-map(.)/symbols/symbol/@char]"
    mode="docx2hub:join-runs">
    <xsl:variable name="target-font" as="xs:string?" select="docx2hub:font-map(.)/symbols/symbol[@char = current()/..][1]/@font"/>
    <xsl:attribute name="{name()}" select="if ($target-font) then $target-font else $docx2hub:symbol-replacement-rfonts/@w:ascii"/>
  </xsl:template>
  
  <xsl:template match="@css:font-family" mode="docx2hub:join-runs" priority="2">
    <xsl:variable name="transformed" as="attribute(css:font-family)">
      <xsl:next-match/>
    </xsl:variable>
    <xsl:variable name="role" as="attribute(role)?">
      <xsl:apply-templates select="../@role" mode="#current"/>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="$transformed = . and ../@docx2hub:map-from = ."><!-- no mapping took place, although it should have -->
        <xsl:attribute name="role" select="string-join(distinct-values((tokenize($role, '\s+'), 'hub:ooxml-symbol')), ' ')"/>
        <xsl:attribute name="annotations" 
          select="string-join(for $i in string-to-codepoints(..) return tr:dec-to-hex($i), ' ')"/>
      </xsl:when>
      <xsl:when test="$role">
        <xsl:attribute name="role" select="$role"/>
      </xsl:when>
    </xsl:choose>
    <xsl:sequence select="$transformed"/>
  </xsl:template>
  
  <xsl:template match="@docx2hub:map-from | @docx2hub:field-function | @docx2hub:sectPr" mode="docx2hub:join-runs"/>


  <xsl:template match="dbk:para[not(@docx2hub:removable)]" mode="docx2hub:join-runs">
    <xsl:call-template name="docx2hub_move-invalid-sidebar-elements"/>
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:variable name="processed-pagebreak-elements" as="item()*">
        <xsl:call-template name="docx2hub:pagebreak-elements-to-attributes"/>
      </xsl:variable>
      <xsl:sequence select="$processed-pagebreak-elements/self::attribute(), $processed-pagebreak-elements/self::dbk:anchor"/>
      <xsl:apply-templates mode="#current"/>
      <xsl:sequence select="$processed-pagebreak-elements/self::dbk:anchors-to-the-end/dbk:anchor"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="*[exists(following-sibling::*[1]/@docx2hub:removable | preceding-sibling::*[1]/@docx2hub:removable)]" 
    mode="docx2hub:join-runs" priority="-0.4">
    <xsl:if test="self::dbk:para">
      <xsl:call-template name="docx2hub_move-invalid-sidebar-elements"/>  
    </xsl:if>
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:variable name="processed-pagebreak-elements" as="item()*">
        <xsl:call-template name="docx2hub:pagebreak-elements-to-attributes"/>
      </xsl:variable>
      <xsl:sequence select="$processed-pagebreak-elements/self::attribute(), $processed-pagebreak-elements/self::dbk:anchor"/>
      <xsl:apply-templates mode="#current"/>
      <xsl:sequence select="$processed-pagebreak-elements/self::dbk:anchors-to-the-end/dbk:anchor"/>
    </xsl:copy>
  </xsl:template>


  <xsl:template match="dbk:para[@docx2hub:removable][not(dbk:anchor[@role eq 'end'][exists(key('docx2hub:linking-item-by-id', @xml:id)/self::dbk:indexterm[@linkends])])]" mode="docx2hub:join-runs" priority="2"/>
  <xsl:template match="dbk:para[dbk:anchor[@role eq 'end'][exists(key('docx2hub:linking-item-by-id', @xml:id)/self::dbk:indexterm[@linkends])]]/@docx2hub:removable" mode="docx2hub:join-runs" priority="2"/>

  <xsl:template name="docx2hub_move-invalid-sidebar-elements">
    <xsl:for-each select=".//dbk:sidebar">
      <xsl:copy copy-namespaces="no">
        <xsl:apply-templates select="@*" mode="#current"/>
        <xsl:attribute name="linkend" select="concat('id_', generate-id(.))"/>
        <xsl:apply-templates select="node()" mode="#current"/>
      </xsl:copy>
    </xsl:for-each>
  </xsl:template>

  <xsl:template name="docx2hub:pagebreak-elements-to-attributes">
    <xsl:apply-templates select=".//dbk:br[@role[not(. eq 'textWrapping')]]
                                          [dbk:same-scope(., current())]" 
      mode="docx2hub:join-runs-br-attr"/>
    <xsl:call-template name="docx2hub:preceding_pagebreak-elements-to-attributes"/>
    <xsl:call-template name="docx2hub:following_pagebreak-elements-to-attributes"/>
  </xsl:template>
  
  <xsl:template name="docx2hub:following_pagebreak-elements-to-attributes">
    <xsl:variable name="following" as="element(dbk:para)?" select="following-sibling::*[1][@docx2hub:removable]"/>
    <xsl:variable name="page-break-atts" as="attribute(*)*">
      <xsl:apply-templates select="$following//dbk:br[@role[not(. eq 'textWrapping')]]
                                                     [dbk:same-scope(., $following)]" 
        mode="docx2hub:join-runs-br-attr"/>  
    </xsl:variable>
    <xsl:sequence select="$page-break-atts[name() = 'css:page-break-after']"/>
    <!-- There may be anchors (from w:bookmarkStart and w:bookmarkEnd) in removable paragraphs -->
    <anchors-to-the-end>
      <xsl:apply-templates select="$following//dbk:anchor[following-sibling::dbk:br[@role[not(. eq 'textWrapping')]]]" mode="#current"/>  
    </anchors-to-the-end>
  </xsl:template>
  
  <xsl:template name="docx2hub:preceding_pagebreak-elements-to-attributes">
    <xsl:variable name="preceding" as="element(dbk:para)?" select="preceding-sibling::*[1][@docx2hub:removable]"/>
    <xsl:variable name="page-break-atts" as="attribute(*)*">
      <xsl:apply-templates select="$preceding//dbk:br[@role[not(. eq 'textWrapping')]]
                                                     [dbk:same-scope(., $preceding)]" 
        mode="docx2hub:join-runs-br-attr"/>  
    </xsl:variable>
    <xsl:sequence select="$page-break-atts[name() = 'css:page-break-before']"/>
    <!-- There may be anchors (from w:bookmarkStart and w:bookmarkEnd) in removable paragraphs -->
    <xsl:apply-templates select="$preceding//dbk:anchor[preceding-sibling::dbk:br[@role[not(. eq 'textWrapping')]]]" mode="#current"/>
  </xsl:template>

  <xsl:function name="tr:signature" as="xs:string?">
    <xsl:param name="node" as="node()?" />
    <xsl:variable name="result-strings" as="xs:string*">
      <xsl:apply-templates select="$node" mode="docx2hub:join-runs-signature" />
    </xsl:variable>
    <xsl:value-of select="string-join($result-strings,'')"/>
  </xsl:function>

  <xsl:template match="dbk:phrase|dbk:superscript|dbk:subscript" mode="docx2hub:join-runs-signature">
    <xsl:sequence select="string-join(
                            (: don't join runs that contain field chars or instrText :)
                            (name(), w:fldChar/@w:fldCharType, w:instrText/name(), tr:attr-hashes(.)), 
                            '___'
                          )" />
  </xsl:template>

  <xsl:template match="dbk:anchor[
                         tr:signature(following-sibling::node()[not(self::dbk:anchor)][1]/self::element())
                         =
                         tr:signature(preceding-sibling::node()[not(self::dbk:anchor)][1]/self::element())
                       ]" mode="docx2hub:join-runs-signature">
    <xsl:apply-templates select="preceding-sibling::node()[not(self::dbk:anchor)][1]" mode="docx2hub:join-runs-signature" />
  </xsl:template>

  <xsl:template match="node()" mode="docx2hub:join-runs-signature">
    <xsl:sequence select="''" />
  </xsl:template>

  <xsl:function name="tr:attr-hashes" as="xs:string*">
    <xsl:param name="elt" as="node()*" />
    <xsl:perform-sort>
      <xsl:sort/>
      <xsl:sequence select="for $a in ($elt/@* except ($elt/@tr:processed, $elt/@srcpath, $elt/@docx2hub:map-from)) 
                            return tr:attr-hash($a)" />
    </xsl:perform-sort>
    <!-- unmappable chars should stay in their own span: --> 
    <xsl:sequence select="$elt[@docx2hub:map-from[. = $elt/@css:font-family]]/generate-id()"/>
  </xsl:function>

  <xsl:function name="tr:attr-hash" as="xs:string">
    <xsl:param name="att" as="attribute(*)" />
    <xsl:sequence select="concat(name($att), '__=__', $att)" />
  </xsl:function>

  <xsl:function name="tr:attname" as="xs:string">
    <xsl:param name="hash" as="xs:string" />
    <xsl:value-of select="replace($hash, '__=__.+$', '')" />
  </xsl:function>

  <xsl:function name="tr:attval" as="xs:string">
    <xsl:param name="hash" as="xs:string" />
    <xsl:value-of select="replace($hash, '^.+__=__', '')" />
  </xsl:function>
  
  <!-- @type = ('column', 'page') --> 
  <xsl:template match="dbk:br[@role[not(. eq 'textWrapping')]]" mode="docx2hub:join-runs-br-attr">
    <xsl:choose>
      <xsl:when test="dbk:before-text-in-para(., ancestor::dbk:para[1])">
        <xsl:attribute name="css:page-break-before" select="'always'"/>
      </xsl:when>
      <xsl:when test="dbk:after-text-in-para(., ancestor::dbk:para[1])">
        <xsl:attribute name="css:page-break-after" select="'always'"/>
      </xsl:when>
      <xsl:otherwise/>
    </xsl:choose>
  </xsl:template>

  <xsl:variable name="dbk:scope-establishing-elements" as="xs:string*"
    select="('annotation', 
             'entry', 
             'blockquote', 
             'figure', 
             'footnote',
             'indexterm',
             'listitem',
             'sidebar',
             'table')"/>

  <xsl:function name="dbk:same-scope" as="xs:boolean">
    <!-- 
      There are situations when you don’t want to select the
      text nodes of an embedded footnote when selecting the text
      nodes of a paragraph.
      A footnote, for example, constitutes a so called “scope.”
      Other scope-establishing elements are table cells that
      may contain paragraphs, or figures/tables whose captions 
      may contain paragraphs. But also indexterms, elements that 
      do not contain paragraphs, may establish a new scope. 
      This concept allows you to select only the main narrative 
      text of a given paragraph (or phrase, …), excluding any 
      content of embedded notes, figures, list items, or index 
      terms.
      Example:
<para><emphasis>Outer</emphasis> para text<footnote><para>Footnote text</para></footnote>.</para>
      Typical invocation (context: outer para):
      .//text()[ens:same-scope(., current())]
      Result: The three text nodes with string content
      'Outer', ' para text', and '.'
      -->
    <xsl:param name="node" as="node()" />
    <xsl:param name="ancestor-elt" as="element(*)*" />
    <xsl:sequence 
      select="not(
                $node/ancestor::*[
                  local-name() = $dbk:scope-establishing-elements]
                  [
                    some $a in ancestor::* 
                    satisfies (
                      some $b in $ancestor-elt 
                      satisfies ($a is $b))
                  ]
                )" />
  </xsl:function>
  
  <xsl:function name="dbk:before-text-in-para" as="xs:boolean">
    <xsl:param name="elt" as="element(*)"/><!-- typically dbk:br[@role = 'page'] -->
    <xsl:param name="para" as="element(dbk:para)"/>
    <xsl:sequence select="not($para//text())
                          or
                          (
                            dbk:same-scope($elt, $para)
                            and
                            not( some $text in $para//text()[dbk:same-scope(., $para)] 
                                 satisfies ($text &lt;&lt; $elt) 
                            )
                          )"/>
  </xsl:function>

  <xsl:function name="dbk:after-text-in-para" as="xs:boolean">
    <xsl:param name="elt" as="element(*)"/><!-- typically dbk:br[@role = 'page'] -->
    <xsl:param name="para" as="element(dbk:para)"/>
    <xsl:sequence select="dbk:same-scope($elt, $para)
                          and
                          not( some $text in $para//text()[dbk:same-scope(., $para)] 
                               satisfies ($text &gt;&gt; $elt) 
                          )"/>
  </xsl:function>

  <xsl:template match="dbk:br[@role[not(. eq 'textWrapping')]]
                             [
                               dbk:before-text-in-para(., ancestor::dbk:para[1])
                               or dbk:after-text-in-para(., ancestor::dbk:para[1])
                             ]" mode="docx2hub:join-runs"/>

  <!-- sidebar -->
  <xsl:template match="dbk:sidebar" mode="docx2hub:join-runs">
    <anchor>
      <xsl:attribute name="xml:id" select="concat('side_', generate-id(.))"/>
    </anchor>
  </xsl:template>

  <!-- mode hub:fix-libre-office-issues -->
  <!-- style names from Libre Office templates are coded in @native-name only, the @name attributes are automatically numbered 'style65' etc.
        therefore the @names are replace by normalized @native-names in paragraphs and css:rules -->
  
  <xsl:function name="docx2hub:normalize-to-css-name" as="xs:string">
    <xsl:param name="style-name" as="xs:string"/>
    <xsl:sequence select="replace(replace(replace($style-name, '[^-_~a-z0-9]', '_', 'i'), '~', '_-_'), '^(\I)', '_$1')"/>
<!--    <xsl:sequence select="replace($style-name, '~', '_-_')"/>-->
  </xsl:function>
  
  <xsl:key name="natives" match="css:rule" use="@name"/> 
  
  <xsl:variable name="is-libre-office-document"
              select="if (/dbk:hub/dbk:info/dbk:keywordset/dbk:keyword[@role = 'source-application'][matches(., '^LibreOffice', 'i')]) 
                      then true() 
                      else false()" as="xs:boolean"/> 
  
  <xsl:template match="css:rule[$is-libre-office-document][matches(@native-name, '^p$')]/@native-name" mode="docx2hub:join-runs">
    <xsl:attribute name="{name()}">
      <xsl:sequence select="'para'"/>
    </xsl:attribute>
  </xsl:template>
  
  <!-- matches(@native-name, '~'): use @native-name instead of @name even if docx is saved by MS Word -->
  <xsl:template match="css:rule[$is-libre-office-document or matches(@native-name, '~')]/@name" mode="docx2hub:join-runs">
    <xsl:attribute name="{name()}">
      <xsl:choose>
        <xsl:when test="matches(../@native-name, '(Kein Absatzformat|^\s*$)')">
          <xsl:sequence select="'None'"/>
        </xsl:when>
        <xsl:when test="matches(../@native-name, '^p$')">
          <xsl:sequence select="'para'"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:sequence select="docx2hub:normalize-to-css-name(../@native-name)"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:attribute> 
  </xsl:template>
  
  <xsl:template match="*[not((local-name(.) = ('keyword', 'keywordset', 'anchor')))]
                        [$is-libre-office-document or matches(key('natives', @role, $root)/@native-name, '~')]/@role" mode="docx2hub:join-runs">
    <xsl:attribute name="{name()}">
      <xsl:choose>
        <xsl:when test="key('natives', .)[matches(@native-name, 'Kein Absatzformat')]">
          <xsl:sequence select="'None'"/>
        </xsl:when>
        <xsl:when test="key('natives', .)[matches(@native-name, '(Einfaches Absatzformat|^p$)', 'i')]">
          <xsl:sequence select="'para'"/>
        </xsl:when>
        <xsl:when test="matches(., 'hub:')">
          <xsl:sequence select="."/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:sequence select="key('natives', .)/docx2hub:normalize-to-css-name(@native-name)"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:attribute> 
  </xsl:template>
  
  <xsl:template match="*:keywordset[@role='fieldVars']" mode="docx2hub:join-runs">
    <xsl:if test="exists(//*:keyword[matches(@role,'^fieldVar_')])">
      <xsl:copy copy-namespaces="no">
        <xsl:apply-templates select="@*" mode="#current"/>
        <xsl:apply-templates select="//*:keyword[matches(@role,'^fieldVar_')]" mode="field-var"/>
      </xsl:copy>  
    </xsl:if>
  </xsl:template>
  
  <xsl:template match="*:keyword[matches(@role,'^fieldVar_')]" mode="field-var">
    <xsl:copy copy-namespaces="no">
      <xsl:attribute name="role" select="replace(@role,'^fieldVar_','')"/>
      <xsl:apply-templates mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="*:keyword[matches(@role,'^fieldVar_')]" mode="docx2hub:join-runs"/>
  
  <!-- This mode has to run before docx2hub:field-functions -->
  
  <xsl:template match="/dbk:hub" mode="docx2hub:join-instrText-runs">
    <!-- This is a newly introduced nesting that largely has the same effect as the existing 
      docx2hub:nest-field-functions nesting ~200 lines down. It solved the issue that instrText
      after a nested inline field function referred to the wrong begin fldChar. 
      It is probably a good idea to try to combine nesting and instrText merging. 
      This could save us an XSLT pass.
      -->
    <xsl:variable name="nested-fldChars" as="document-node(element(dbk:nested-fldChars))">
      <xsl:document>
        <nested-fldChars>
          <xsl:variable name="labeled-fldChars"  as="element()*">
            <xsl:for-each select=".//w:fldChar | .//w:instrText">
              <xsl:variable name="count-preceding-begin" as="xs:integer" select="count(preceding::w:fldChar[@w:fldCharType = 'begin'])"/>
              <xsl:variable name="count-preceding-end" as="xs:integer" select="count(preceding::w:fldChar[@w:fldCharType = 'end'])"/>
              <xsl:variable name="self-non-begin" as="xs:integer" select="count((self::w:instrText, self::w:fldChar[@w:fldCharType = ('separate', 'end')]))"/>
              <xsl:copy>
                <xsl:sequence select="@*"/>
                <xsl:attribute name="docx2hub:fldChar-level" select="
                  $count-preceding-begin
                  - $count-preceding-end
                  - $self-non-begin"/>
                <xsl:sequence select="node()"/>
              </xsl:copy>
            </xsl:for-each>
          </xsl:variable>
          <xsl:if test="exists($labeled-fldChars) and not(xs:integer($labeled-fldChars[last()]/@docx2hub:fldChar-level) eq 0)">
            <xsl:message terminate="{$terminate-on-unbalanced-instrTexts}">
              <xsl:text>Non-balanced field char nesting detected in mode docx2hub:join-instrText-runs. "level" of last fldChar should be 0, but is: </xsl:text>
              <xsl:value-of select="$labeled-fldChars[last()]/@docx2hub:fldChar-level"/>
            </xsl:message>
          </xsl:if>
          <xsl:sequence select="tr:nest-fldChars($labeled-fldChars, 0)"/>  
        </nested-fldChars>
      </xsl:document>
    </xsl:variable>
    <xsl:next-match>
      <xsl:with-param name="nested-fldChars" select="$nested-fldChars" tunnel="yes"/>
      <xsl:with-param name="footnotePrs" as="element(w:footnotePr)*" select="descendant-or-self::w:footnotePr" tunnel="yes"/>
      <xsl:with-param name="sect-boundaries" as="element(*)*" select="descendant-or-self::*[@docx2hub:sectPr] | w:sectPr" tunnel="yes"/>
    </xsl:next-match>
  </xsl:template>
  
  <xsl:function name="tr:nest-fldChars-unlabeled" as="element(*)*">
    <xsl:param name="input" as="element(*)*"/><!-- w:fldChar, w:instrText or dbk:fldCharGroup -->
    <xsl:param name="depth" as="xs:integer"/><!-- pass 0 when invoking the function from outside the function -->
    <xsl:variable name="nest" as="element(*)*">
      <xsl:for-each-group select="$input" group-starting-with="w:fldChar[@w:fldCharType = 'begin']">
        <xsl:for-each-group select="current-group()" group-ending-with="w:fldChar[@w:fldCharType = 'end']">
          <xsl:choose>
            <xsl:when test="exists(current-group()/self::w:fldChar[@w:fldCharType = 'begin'])
              and
              exists(current-group()/self::w:fldChar[@w:fldCharType = 'end'])">
              <fldCharGroup begin="{current-group()/self::w:fldChar[@w:fldCharType = 'begin']/@xml:id}"
                end="{current-group()/self::w:fldChar[@w:fldCharType = 'end']/@xml:id}">
                <xsl:if test="exists(current-group()/self::w:fldChar[@w:fldCharType = 'separate']/@xml:id)">
                  <xsl:attribute name="separate" 
                    select="current-group()/self::w:fldChar[@w:fldCharType = 'separate']/@xml:id"/>
                </xsl:if>
                <xsl:sequence select="current-group()"/>
              </fldCharGroup>
            </xsl:when>
            <xsl:otherwise>
              <xsl:sequence select="current-group()"/>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each-group>
      </xsl:for-each-group>  
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="$depth ge 20">
        <xsl:message terminate="yes">
          <xsl:text>Non-balanced (or too deeply nested) field char nesting detected in mode docx2hub:join-instrText-runs: </xsl:text>
          <xsl:sequence select="$nest"/>
        </xsl:message>
      </xsl:when>
      <xsl:when test="exists($nest/self::w:fldChar)">
        <xsl:sequence select="tr:nest-fldChars-unlabeled($nest, $depth + 1)"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:sequence select="$nest"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>
  
  <xsl:function name="tr:same-level" as="xs:boolean">
    <xsl:param name="fldChar" as="element()"/>
    <xsl:param name="depth" as="xs:integer"/>
    <xsl:sequence select="xs:integer($fldChar/@docx2hub:fldChar-level) eq $depth"/>
  </xsl:function>
  
  <xsl:function name="tr:nest-fldChars-labeled" as="element(*)*">
    <xsl:param name="input" as="element(*)*"/><!-- w:fldChar, w:instrText or dbk:fldCharGroup -->
    <xsl:param name="depth" as="xs:integer"/><!-- pass 0 when invoking the function from outside the function -->
    <xsl:for-each-group select="$input[xs:integer(@docx2hub:fldChar-level) ge $depth]" group-by="tr:same-level(., $depth)" >
      <xsl:for-each-group select="current-group()" group-ending-with="w:fldChar[@w:fldCharType = 'end'][tr:same-level(., $depth)]">
        <xsl:variable name="cur-level" select="current-group()[tr:same-level(.,$depth)]" as="node()*"/>
        <xsl:if test="exists($cur-level/self::w:fldChar[@w:fldCharType = 'begin'])
          and
          exists($cur-level/self::w:fldChar[@w:fldCharType = 'end'])">
          <fldCharGroup
            begin="{current-group()/self::w:fldChar[@w:fldCharType = 'begin']/@xml:id}"
            end="{current-group()/self::w:fldChar[@w:fldCharType = 'end']/@xml:id}">
            <xsl:if test="exists(current-group()/self::w:fldChar[@w:fldCharType = 'separate']/@xml:id)">
              <xsl:attribute name="separate" 
                select="current-group()/self::w:fldChar[@w:fldCharType = 'separate']/@xml:id"/>
            </xsl:if>
          </fldCharGroup>
        </xsl:if>
        <xsl:sequence select="tr:nest-fldChars(current-group() except $cur-level, $depth + 1)"/>
      </xsl:for-each-group>
    </xsl:for-each-group>
  </xsl:function>
  
  <xsl:function name="tr:nest-fldChars" as="element(*)*">
    <xsl:param name="input" as="element(*)*"/><!-- w:fldChar, w:instrText or dbk:fldCharGroup -->
    <xsl:param name="depth" as="xs:integer"/><!-- pass 0 when invoking the function from outside the function -->
    <xsl:choose>
      <xsl:when test="empty($input/self::w:fldChar)"/>
      <xsl:when test="exists($input/self::w:fldChar/@docx2hub:fldChar-level)">
        <xsl:sequence select="tr:nest-fldChars-labeled($input, $depth)"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:sequence select="tr:nest-fldChars-unlabeled($input, $depth)"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:function>  

  <!-- Indexterm processing should happen after symbol processing.
    Now this mode needs to have a collection($collection-uri) input including fontmaps and an XML catalog, too. -->
  <xsl:template match="*[w:r/w:instrText]" mode="docx2hub:join-instrText-runs">
    <xsl:param name="nested-fldChars" as="document-node(element(dbk:nested-fldChars))" tunnel="yes"/>
    <xsl:copy copy-namespaces="no">
      <xsl:call-template name="docx2hub:adjust-lang"/>
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:for-each-group select="*" 
        group-adjacent="exists(
                          self::w:r
                                   [every $c in * 
                                    satisfies $c/(self::w:instrText | self::w:br | self::w:softHyphen | self::w:tab 
                                                  | self::w:noBreakHyphen
                                                  (: w:br appeared in comments in 12181_2015_0024_Manuscript.docm, 
                                                     w:tab in DIN_5008_D_st.docx :)
                                                 )
                                   ]
                          | self::w:fldSimple (: prEN_16815 :)
                          | self::m:oMath[preceding-sibling::*[empty(self::m:oMath)][1]/self::w:r[w:instrText]] (: hanser_loeser_omml_index :)
                          | self::w:r[w:sym][count(*) = 1]
                          | self::w:r[w:object/mml:math][count(* except w:rPr) = 1]
                                     [preceding-sibling::*[empty(w:object/mml:math)][1]/self::w:r[w:instrText]]
                          | self::*:superscript | self::*:subscript
                          | self::w:bookmarkStart | self::w:bookmarkEnd)"><!-- the _GoBack bookmark might be here -->
        <xsl:choose>
          <xsl:when test="current-grouping-key() 
                          and 
                          exists(current-group()/(self::w:r[w:instrText] | self::w:fldsimple | self::m:oMath))">
            <!-- Typically /dbk:hub, but sometimes also /dbk:p or /w:p -->
            <xsl:variable name="mode-root" as="document-node(element(*))" select="root()"/>
            <xsl:variable name="fldCharGroup0" as="element(dbk:fldCharGroup)?"
              select="(
                        $nested-fldChars//dbk:fldCharGroup[key('docx2hub:item-by-id', @begin, $mode-root) &lt;&lt; current()]
                                                          [key('docx2hub:item-by-id', @end, $mode-root) &gt;&gt; current()
                                                           and not(
                                                            (: DIN_EN_ISO_21563_tr_13035449.docx :)
                                                            key('docx2hub:item-by-id', @separate, $mode-root) &lt;&lt; current()
                                                           )]
                      )[last()]"/>
            <!-- 
              Accepting an empty dbk:fldCharGroup is a workaround for EndNote citations that span across paragraph boundaries 
              in footnotes. This is problematic because of the template that currently begins on line 1489, 
              <xsl:template match="w:footnote/w:p[1][*[docx2hub:element-is-footnoteref(.)]]" mode="docx2hub:join-instrText-runs" priority="1"> 
              since it sets the document scope to a single w:p.
              A rework of the first-w:p-in-footnote preprocessing might be necessary, or a warning for 
              paragraph-spanning field functions in footnotes.
              https://redmine.le-tex.de/issues/13271
            -->
            <xsl:variable name="fldCharGroup" as="element(dbk:fldCharGroup)"
              select="if ($fldCharGroup0) then $fldCharGroup0
              else ($nested-fldChars//dbk:fldCharGroup[key('docx2hub:item-by-id', @begin, $mode-root) &lt;&lt; current()])[last()]"/>
            <xsl:if test="count($fldCharGroup0) = 0">
              <xsl:message select="'End field char out of scope for ', $fldCharGroup"/>
            </xsl:if>
            <xsl:variable name="start" as="element(w:fldChar)" 
              select="key('docx2hub:item-by-id', $fldCharGroup/@begin, $mode-root)"/>
            <xsl:variable name="end" as="element(w:fldChar)?" 
              select="key('docx2hub:item-by-id', $fldCharGroup/@end, $mode-root)"/>
            <w:r>
              <xsl:if test="$srcpaths = 'yes' and current-group()/@srcpath">
                <xsl:attribute name="srcpath" select="current-group()/@srcpath" separator=" "/>
              </xsl:if>
              <xsl:variable name="preceding-begin" as="element(w:fldChar)"
                select="(current-group()/w:instrText)[1]/preceding::w:fldChar[@w:fldCharType = 'begin'][1]"/>
              <xsl:variable name="following-end" as="element(w:fldChar)?"
                select="(current-group()/w:instrText)[1]/following::w:fldChar[@w:fldCharType = 'end'][1]"/>
              <w:instrText xsl:exclude-result-prefixes="#all">
                <xsl:variable name="is-index-entry" as="xs:boolean" 
                  select="matches(string-join(current-group()/w:instrText/text(), ''), '^\s*XE\s+', 'i')"/>
                <xsl:variable name="instr-text-nodes" as="document-node()">
                  <xsl:document>
                    <xsl:apply-templates select="current-group()/(w:instrText 
                                                                 (:| self::w:fldSimple/@w:instr 
                                                                 | self::w:fldSimple/w:r/w:instrText:)
                                                                 | self::w:fldSimple
                                                                 | w:sym[parent::w:r]
                                                                 | w:object[mml:math][parent::w:r]
                                                                 | self::*:superscript | self::*:subscript
                                                                 | w:noBreakHyphen | w:br | w:tab | w:softHyphen
                                                                 | self::m:oMath (: may occur in XE :))
                                                                [. >> $preceding-begin]"
                                         mode="docx2hub:join-instrText-runs_save-formatting">
                      <xsl:with-param name="formatting-acceptable" as="xs:boolean" tunnel="yes" select="$is-index-entry"/>
                      <xsl:with-param name="indexterm-preprocessing" as="xs:boolean" tunnel="yes" select="$is-index-entry"/>
                    </xsl:apply-templates>
                  </xsl:document>
                </xsl:variable>
                <!-- docx2hub:join-instrText-runs_render-compound1 is for rendering the instrText as text for attributes,
                     docx2hub:join-instrText-runs_render-compound2 is for rendering it with markup
                     docx2hub:join-instrText-runs_render-compound3 is for postprocessing the joint transformed instrText 
                        content just in case there is a backslash in one instrText and the quote in the next 
                        (https://redmine.le-tex.de/issues/8174, https://redmine.le-tex.de/issues/17220) -->
                <xsl:variable name="instr-text" as="node()*">
                  <xsl:apply-templates select="$instr-text-nodes" mode="docx2hub:join-instrText-runs_render-compound1"/>
                </xsl:variable>
                <xsl:variable name="instr-text-string" as="xs:string" select="string-join($instr-text, '')"/>
                <xsl:variable name="formatting-acceptable" as="xs:boolean" 
                  select="matches($instr-text-string, '^\s*(xe[\s\p{Zs}]+|&quot;\s*$)', 'i')">
                  <!-- &quot;\s*$ is there when there is, for ex. { XE Lagerstättenabschluss \t "6.8" }
                    with a REF around the 6.8 (“see Sect. 6.8”). It is separated from the first part
                  of the XE instrText. But we don’t know yet that they belong together since they haven’t 
                  been grouped yet. This is a mess. See https://tickets.le-tex.de/view.php?id=7060#c25632 -->
                </xsl:variable>
                <xsl:attribute name="docx2hub:fldChar-start-id" 
                  select="if ($following-end/@xml:id = $end/@xml:id) 
                          then $start/@xml:id
                          else $preceding-begin/@xml:id"/>
                <xsl:choose>
                  <xsl:when test="empty($instr-text-nodes/node())">
                    <xsl:attribute name="docx2hub:field-function-name" select="'BROKEN3'"/>
                    <xsl:attribute name="docx2hub:field-function-error" select="'missing or wrongly named w:instrText element'"/>
                  </xsl:when>
                  <xsl:when test="not($start/@xml:id = $preceding-begin/@xml:id)
                                  and 
                                  ($following-end/@xml:id = $end/@xml:id)">
                    <xsl:attribute name="docx2hub:field-function-continuation-for" select="$start/@xml:id"/>
                    <xsl:attribute name="docx2hub:preceding-begin" select="$preceding-begin/@xml:id"/>
                    <xsl:variable name="wrapper" as="element(dbk:wrapper)">
                      <wrapper>
                        <xsl:apply-templates select="$instr-text-nodes" mode="docx2hub:join-instrText-runs_render-compound2">
                          <xsl:with-param name="formatting-acceptable" as="xs:boolean?" tunnel="yes"  
                            select="$formatting-acceptable"/>
                        </xsl:apply-templates>    
                      </wrapper>
                    </xsl:variable>
                    <xsl:apply-templates select="$wrapper" mode="docx2hub:join-instrText-runs_render-compound3">
                      <xsl:with-param name="formatting-acceptable" as="xs:boolean?" tunnel="yes"  
                        select="$formatting-acceptable"/>
                    </xsl:apply-templates>
                  </xsl:when>
                  <xsl:when test="not($start/@xml:id = $preceding-begin/@xml:id)">
                    <xsl:attribute name="docx2hub:preceding-begin" select="$preceding-begin/@xml:id"/>
                    <xsl:variable name="wrapper" as="element(dbk:wrapper)">
                      <wrapper>
                        <xsl:apply-templates select="$instr-text-nodes" mode="docx2hub:join-instrText-runs_render-compound2">
                          <xsl:with-param name="formatting-acceptable" as="xs:boolean?" tunnel="yes"  
                            select="$formatting-acceptable"/>
                        </xsl:apply-templates>    
                      </wrapper>
                    </xsl:variable>
                    <xsl:apply-templates select="$wrapper" mode="docx2hub:join-instrText-runs_render-compound3">
                      <xsl:with-param name="formatting-acceptable" as="xs:boolean?" tunnel="yes"  
                        select="$formatting-acceptable"/>
                    </xsl:apply-templates>
                  </xsl:when>
                  <xsl:when test="matches($instr-text-string, '^\s*ADDIN\s+(ZOTERO_ITEM\s+)?CSL_CITATION', 's')">
                    <xsl:attribute name="docx2hub:field-function-name" select="'CSL_JSON'"/>
                    <xsl:attribute name="docx2hub:field-function-args" 
                      select="replace($instr-text-string, '^\s*ADDIN\s+(ZOTERO_ITEM\s+)?CSL_CITATION\s+(\{.+\})\s*$', '$2', 's')"/>
                  </xsl:when>
                  <xsl:when test="matches($instr-text-string, '^\s*ADDIN\s+(Mendeley\s+Bibliography|ZOTERO_BIBL).+CSL_BIBLIOGRAPHY', 'si')">
                    <xsl:attribute name="docx2hub:field-function-name" select="'CSL_XML'"/>
                    <xsl:attribute name="docx2hub:field-function-args" 
                      select="replace($instr-text-string, '^\s*ADDIN\s+(Mendeley\s+Bibliography|ZOTERO_BIBL).+CSL_BIBLIOGRAPHY\s+', '', 'si')"/>
                  </xsl:when>
                  <xsl:when test="matches($instr-text-string, '^ADDIN\s+CitaviPlaceholder', 's')">
                    <xsl:attribute name="docx2hub:field-function-name" select="'CITAVI_JSON'"/>
                    <xsl:attribute name="docx2hub:field-function-args" 
                      select="replace($instr-text-string, '^ADDIN\s+CitaviPlaceholder\{(.+)\}$', '$1', 's')"/>
                  </xsl:when>
                  <xsl:when test="matches($instr-text-string, '^ADDIN\s+CITAVI\.PLACEHOLDER', 's')">
                    <xsl:attribute name="docx2hub:field-function-name" select="'CITAVI_JSON'"/>
                    <xsl:attribute name="docx2hub:field-function-args" 
                      select="replace($instr-text-string, '^ADDIN\s+CITAVI\.PLACEHOLDER\s+(.+?)\s+(.+)$', '$2', 's')"/>
                    <xsl:attribute name="docx2hub:citation-uuid" 
                      select="replace($instr-text-string, '^ADDIN\s+CITAVI\.PLACEHOLDER\s+(.+?)\s+(.+)$', '$1', 's')"/>
                  </xsl:when>
                  <xsl:when test="matches($instr-text-string, '^ADDIN\s+CITAVI\.?BIBLIOGRAPHY', 'si')">
                    <xsl:attribute name="docx2hub:field-function-name" select="'CITAVI_XML'"/>
                    <xsl:attribute name="docx2hub:field-function-args" 
                      select="replace($instr-text-string, '^ADDIN\s+CITAVI\.?BIBLIOGRAPHY\s+', '', 'si')"/>
                  </xsl:when>
                  <xsl:when test="matches($instr-text-string, 'FORMCHECKBOX', 's')">
                    <xsl:attribute name="docx2hub:field-function-name" select="$instr-text-string"/>
                    <xsl:variable name="prec" select="(preceding-sibling::*[w:fldChar[@w:fldCharType='begin']])[last()]" as="node()?"/>
                    <xsl:attribute name="docx2hub:field-function-args" 
                      select="$prec/w:fldChar[@w:fldCharType='begin']/@w:val"/>
                    <!-- see w:ffData handling too -->
                  </xsl:when>
                  <xsl:when test="$instr-text-nodes/w:instrText/@docx2hub:field-function-name = ('CITAVI_JSON', 'CSL_JSON')">
                    <xsl:attribute name="docx2hub:field-function-name" select="$instr-text-nodes/w:instrText/@docx2hub:field-function-name"/>
                    <xsl:attribute name="docx2hub:field-function-args" select="$instr-text-nodes/w:instrText/@docx2hub:field-function-args"/>
                  </xsl:when>
                  <xsl:when test="matches($instr-text-string, '^https?')">
                    <xsl:attribute name="docx2hub:field-function-name" select="'HYPERLINK'"/>
                    <xsl:attribute name="docx2hub:field-function-args" select="$instr-text-string"/>
                  </xsl:when>
                  <xsl:when test="matches(tokenize($instr-text-string,'\s+')[not(.='')][1],'\.(tiff?|png|jpe?g|gif)','i')">
                    <xsl:attribute name="docx2hub:field-function-name" select="'INCLUDEPICTURE'"/>
                    <xsl:attribute name="docx2hub:field-function-args" select="replace($instr-text-string,'”','&#34;')"/>
                  </xsl:when>
                  <xsl:otherwise>
                    <xsl:variable name="prelim" as="attribute()*">
                      <xsl:analyze-string select="$instr-text-string" regex="^\s*\\?(\i\c*)[\s\p{{Zs}}]*">
                        <xsl:matching-substring>
                          <xsl:attribute name="docx2hub:field-function-name" select="upper-case(regex-group(1))">
                            <!-- upper-case: for the rare (and maybe user error) case of 'xe' for index terms -->
                          </xsl:attribute>
                          <xsl:if test="empty(regex-group(1))">
                            <xsl:attribute name="docx2hub:field-function-name" select="'BROKEN1'"/>
                            <xsl:attribute name="docx2hub:field-function-error" 
                              select="string-join(('not a proper field function name:', .), ' ')"/>
                          </xsl:if>
                        </xsl:matching-substring>
                        <xsl:non-matching-substring>
                          <!-- use replace to de-escape Words quote escape fldArgs="&#34;\„Fenster offen\“-Erkennung&#34;" -->
                          <!-- use replace to fix wrong applied quotes/ spaces in Word fldArgs="&#34; Very-Low-Cycle-Fatigue, VLCF&#34;" -->
                          <!-- <w:instrText xml:space="preserve"> XE „Emotion“ </w:instrText> fldArgs="„Emotion“" -->
                          <xsl:attribute name="docx2hub:field-function-args" 
                                         select="replace(
                                                      replace(
                                                              normalize-space(replace(
                                                                                  replace(
                                                                                          .,
                                                                                          '^(&#34;)\s*(.+)$',
                                                                                          '$1$2'),
                                                                                  '\s*(&#34;)$',
                                                                                  '$1')),
                                                              '\\([&#x201e;&#x201c;])',
                                                              '$1'),
                                                      '(^|\\)&#x201e;(.+[^\\])&#x201c;$',
                                                      '&#34;$2&#34;')"/>
                        </xsl:non-matching-substring>
                      </xsl:analyze-string>
                    </xsl:variable>
                    <xsl:choose>
                      <xsl:when test="count($prelim) = 0">
                        <xsl:message select="'EMPTY $instr-text-string ATTRs for these $instr-text-nodes: ', $instr-text-nodes"></xsl:message>
                      </xsl:when>
                      <xsl:when test="count($prelim) = 1 and not(matches($prelim[1], '^\i\c*$'))">
                        <xsl:attribute name="docx2hub:field-function-name" select="'BROKEN2'"/>
                        <xsl:attribute name="docx2hub:field-function-error" 
                          select="string-join(('not a proper field function name:', $prelim), ' ')"/>
                      </xsl:when>
                      <xsl:otherwise>
                        <xsl:sequence select="$prelim"/>
                        <xsl:variable name="wrapper" as="element(dbk:wrapper)">
                          <wrapper>
                            <xsl:apply-templates select="$instr-text-nodes" mode="docx2hub:join-instrText-runs_render-compound2">
                              <xsl:with-param name="formatting-acceptable" as="xs:boolean?" tunnel="yes"  
                                select="$formatting-acceptable"/>
                            </xsl:apply-templates>    
                          </wrapper>
                        </xsl:variable>
                        <xsl:apply-templates select="$wrapper" mode="docx2hub:join-instrText-runs_render-compound3">
                          <xsl:with-param name="formatting-acceptable" as="xs:boolean?" tunnel="yes"  
                            select="$formatting-acceptable"/>
                        </xsl:apply-templates>
                      </xsl:otherwise>
                    </xsl:choose>
                  </xsl:otherwise>
                </xsl:choose>
              </w:instrText>
            </w:r>
            <xsl:sequence select="current-group()/(self::w:bookmarkStart | self::w:bookmarkEnd)"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:apply-templates select="current-group()" mode="#current"/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each-group>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="* | @*" mode="docx2hub:join-instrText-runs_render-compound1">
    <xsl:value-of select="."/>
  </xsl:template>
  
  <xsl:template match="*" mode="docx2hub:join-instrText-runs_render-compound2">
    <xsl:value-of select="."/>
  </xsl:template>

  <xsl:template match="@*" mode="docx2hub:join-instrText-runs_render-compound2">
    <xsl:copy/>
  </xsl:template>
  
  <xsl:template match="node() | @*" mode="docx2hub:join-instrText-runs_save-formatting">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="w:r/w:sym" mode="docx2hub:join-instrText-runs_save-formatting">
    <xsl:copy>
      <xsl:apply-templates select="../@*, @*, node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="w:fldSimple" 
    mode="docx2hub:join-instrText-runs_render-compound2" priority="3">
    <!-- this should be covered by $instr-text-nodes in the long template above, but apparently it isn’t -->
<!--    <xsl:message select="'!!!!!!!!!!!!!!!!!!!!!!!'"></xsl:message>-->
    <xsl:copy copy-namespaces="no">
      <xsl:sequence select="@w:instr"/>
      <xsl:analyze-string select="@w:instr" regex="^\s*(\w+)(\s+(.+?))?\s*$">
        <xsl:matching-substring>
          <xsl:attribute name="docx2hub:field-function-name" select="upper-case(regex-group(1))"/>
          <xsl:if test="exists(regex-group(2))">
            <xsl:attribute name="docx2hub:field-function-args" select="normalize-space(regex-group(2))"/>
          </xsl:if>
        </xsl:matching-substring>
      </xsl:analyze-string>
      <xsl:apply-templates mode="#current"/>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="w:object[mml:math]" mode="docx2hub:join-instrText-runs_render-compound2">
    <xsl:sequence select="."/>
  </xsl:template>
  
  <xsl:template match="dbk:phrase" mode="docx2hub:join-instrText-runs_render-compound2">
    <!-- already created because of run formatting in mode docx2hub:join-instrText-runs_save-formatting,
         https://github.com/transpect/docx2hub/issues/26 -->
    <xsl:sequence select="."/>
  </xsl:template>
  
  <xsl:template match="w:br | w:tab" 
    mode="docx2hub:join-instrText-runs_render-compound1 docx2hub:join-instrText-runs_render-compound2">
    <xsl:param name="markup-acceptable" as="xs:boolean?" tunnel="yes"/>
    <xsl:choose>
      <xsl:when test="$markup-acceptable">
        <xsl:apply-templates select="." mode="wml-to-dbk"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:text xml:space="preserve"> </xsl:text>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="w:noBreakHyphen | w:softHyphen" 
    mode="docx2hub:join-instrText-runs_render-compound1 docx2hub:join-instrText-runs_render-compound2">
    <xsl:apply-templates select="." mode="wml-to-dbk"/>
  </xsl:template>

  <xsl:template match="w:fldSimple[matches(@w:instr, $w:fldSimple-REF-regex)]" 
    mode="docx2hub:join-instrText-runs_render-compound2_" priority="3">
    <xsl:sequence select="."/>
<!--    <xsl:message select="'222222222222222'"></xsl:message>-->
  </xsl:template>
  
  <xsl:template match="w:fldSimple" mode="docx2hub:join-instrText-runs_render-compound1" priority="3">
    <xsl:value-of select="@w:instr, ." separator=""/>
<!--    <xsl:message select="'11111111111111111111111'"></xsl:message>-->
  </xsl:template>
  
  <xsl:template match="dbk:instrAtt" mode="wml-to-dbk">
    <xsl:processing-instruction name="instrAtt" select="."></xsl:processing-instruction>
  </xsl:template>
  
  <xsl:template match="w:instrText" mode="docx2hub:join-instrText-runs_render-compound2" priority="2">
<!--    <xsl:comment select="'AAAAAAAAAAAa'"></xsl:comment>-->
    <xsl:apply-templates select="if (@xml:space = 'preserve' or exists(text()[normalize-space()]))
                                 then node()
                                 else *" mode="#current"/>
  </xsl:template>
  
  <xsl:template match="w:sym" 
    mode="docx2hub:join-instrText-runs_render-compound1 docx2hub:join-instrText-runs_render-compound2" priority="1">
    <xsl:apply-templates select="." mode="wml-to-dbk"/>
  </xsl:template>
  
  <xsl:variable name="quot-like-regex" as="xs:string" select="'&quot;„“”»«'"/>
  
  <xsl:template name="docx2hub:instrText-formatting" match="w:r[@* except @srcpath]/w:instrText/text()" mode="docx2hub:join-instrText-runs_save-formatting">
    <!-- This template was originally only called by name in mode docx2hub:join-instrText-runs_render-compound2.
         In the course of addressing https://github.com/transpect/docx2hub/issues/26, we also made it match in 
         mode docx2hub:join-instrText-runs_save-formatting. The reason is that in render-compound2, the w:r
         context isn’t available any more. Previously, if any of the w:r parents of a w:instrText join group
         had some attribute (apart from @srcpath), the whole group inherited this attribute (typically @role
         or @css:*). This led to the whole indexterm being italicized oder subscripted in the examples given
         in aforementioned GitHub issue.
    -->
    <xsl:param name="instrText" as="element(w:instrText)" select=".."/>
    <xsl:param name="string" as="xs:string" select="."/>
    <xsl:param name="formatting-acceptable" as="xs:boolean?" tunnel="yes"/>
    <xsl:param name="indexterm-preprocessing" as="xs:boolean?" tunnel="yes"/>
    <xsl:variable name="run-atts" as="attribute(*)*" select="$instrText/parent::w:r/(@* except @srcpath)"/>
    
    <xsl:variable name="prelim" as="item()*">
    <xsl:choose>
      <xsl:when test="$formatting-acceptable">
        <xsl:analyze-string select="$string" flags="i"
          regex="(\\:|[:;{$quot-like-regex}]|(\s|^)\\[a-z]|\\[{$quot-like-regex}]|^\s*XE\s*)">
          <xsl:matching-substring>
            <xsl:choose>
              <xsl:when test="$indexterm-preprocessing">
                <xsl:value-of select="."/>
              </xsl:when>
              <xsl:when test="matches(., '^\s*XE\s*', 'i')">
                <xsl:value-of select="."/>
              </xsl:when>
              <xsl:when test=". = '\:'">
                <xsl:text>:</xsl:text>
              </xsl:when>
              <xsl:when test=". = ':'">
                <sep/>
              </xsl:when>
              <xsl:when test=". = ';'">
                <sortkey/>
              </xsl:when>
              <xsl:when test=". = '&quot;'">
                <quot>
                  <xsl:value-of select="."/>
                </quot>
              </xsl:when>
              <xsl:when test="matches(., concat('^[', $quot-like-regex,']$'))">
                <quot>
                  <xsl:value-of select="."/>
                </quot>
              </xsl:when>
              <xsl:when test="matches(., concat('^\\[', $quot-like-regex, ']$'))">
                <xsl:choose>
                  <xsl:when test="exists($run-atts)">
                    <!-- this shouldn’t be reached since $run-atts can only exist in mode
                      docx2hub:join-instrText-runs_save-formatting which is handled in an xsl:when 
                      above (passthru output without a phrase, so that docx2hub:join-instrText-runs_render-compound2
                      can see elements such as quot and sep without surrounding phrases -->
                    <phrase>
                      <xsl:sequence select="$run-atts"/>
                      <xsl:value-of select="."/>
                    </phrase>
                  </xsl:when>
                  <xsl:when test="exists($instrText/@css:*)">
                    <phrase>
                      <xsl:sequence select="$instrText/@css:*"/>
                      <xsl:value-of select="substring(., 2)"/>
                    </phrase>
                  </xsl:when>
                  <xsl:otherwise>
                    <xsl:value-of select="substring(., 2)"/>
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:when>
              <xsl:when test="matches(., '^\s*\\[a-z]$')">
                <xsl:analyze-string select="." regex="^(\s*)(\\[a-z])$">
                  <xsl:matching-substring>
                    <xsl:value-of select="regex-group(1)"/>
                    <flag>
                      <xsl:value-of select="regex-group(2)"/>
                    </flag>    
                  </xsl:matching-substring>
                </xsl:analyze-string>
              </xsl:when>
            </xsl:choose>
          </xsl:matching-substring>
          <xsl:non-matching-substring>
            <xsl:choose>
              <xsl:when test="exists($run-atts)">
                <phrase>
                  <xsl:sequence select="$run-atts"/>
                  <xsl:value-of select="."/>
                </phrase>
              </xsl:when>
              <xsl:when test="exists($instrText/@css:*)">
                <phrase>
                  <xsl:sequence select="$instrText/@css:*"/>
                  <xsl:value-of select="."/>
                </phrase>
              </xsl:when>
              <xsl:otherwise>
                <xsl:value-of select="."/>
              </xsl:otherwise>
            </xsl:choose>
          </xsl:non-matching-substring>
        </xsl:analyze-string>    
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="$string"/>
      </xsl:otherwise>
    </xsl:choose>
    </xsl:variable>
    <!--<xsl:if test="xs:string(saxon:current-mode-name()) = 'docx2hub:join-instrText-runs_save-formatting'">
      <xsl:message select="'PPPPPPP ', $prelim"></xsl:message>
    </xsl:if>-->
    <xsl:sequence select="$prelim"/>
  </xsl:template>
  
  <xsl:template match="*:XE/dbk:sep[preceding-sibling::dbk:flag]" mode="wml-to-dbk">
    <xsl:choose>
      <xsl:when test="exists(preceding-sibling::node()[1]/self::dbk:phrase[@* except @srcpath] 
                             | following-sibling::node()[1]/self::dbk:phrase[@* except @srcpath])">
        <!-- GI 2023-11-14: I found no way to attach these attributes to sep directly in docx2hub:instrText-formatting above.
          The $instrText for sep was in a document node while the $instrText for the phrases had w:r parents with CSSa
          attributes.
          https://redmine.le-tex.de/issues/15824#note-8 -->
        <phrase>
          <xsl:apply-templates select="(preceding-sibling::node()[1]/self::dbk:phrase 
                                        | following-sibling::node()[1]/self::dbk:phrase)/(@* except @srcpath)" mode="#current"/>
          <xsl:text>:</xsl:text>
        </phrase>
      </xsl:when>
      <xsl:otherwise>
        <xsl:text>:</xsl:text>    
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="w:instrText/text()" mode="docx2hub:join-instrText-runs_render-compound2" priority="0.8">
    <xsl:call-template name="docx2hub:instrText-formatting">
      <xsl:with-param name="instrText" as="element(w:instrText)" select=".."/>
       <xsl:with-param name="string" as="xs:string" select="."/>
     </xsl:call-template>
   </xsl:template>

  <xsl:template match="w:instrText[1][../preceding-sibling::*[1]/self::w:r/w:fldChar[@w:fldCharType = 'begin']]/node()[1][self::text()]" 
    mode="docx2hub:join-instrText-runs_render-compound2" priority="1.5">
    <xsl:call-template name="docx2hub:instrText-formatting">
      <xsl:with-param name="instrText" as="element(w:instrText)" select=".."/>
      <xsl:with-param name="string" as="xs:string" select="replace(., '^\s*\w+[\p{Zs}\s]+', '')"/>
     </xsl:call-template>
    <xsl:comment>foo</xsl:comment>
   </xsl:template>

  
  
  <xsl:template match="dbk:wrapper/text() | dbk:wrapper/*/text()" mode="docx2hub:join-instrText-runs_render-compound3" priority="0.8">
    <xsl:param name="formatting-acceptable" as="xs:boolean" tunnel="yes"/>
    <xsl:variable name="prelim" as="xs:string">
      <xsl:choose>
        <xsl:when test="ends-with(., '\') and (. | ..[parent::dbk:wrapper])/following-sibling::*[1]/local-name() = ('sep', 'quot')">
          <xsl:sequence select="replace(., '\\$', '')"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:sequence select="."/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="(. is parent::dbk:wrapper/node()[1] or . is parent::dbk:wrapper/node()[1]/text()[1]) and $formatting-acceptable">
        <xsl:value-of select="replace($prelim, '^\s*\w+\s+', '')">
          <!-- remove field function name -->
        </xsl:value-of>
      </xsl:when>
      <xsl:otherwise>
          <xsl:value-of select="$prelim"/>
        </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="dbk:wrapper/dbk:quot[ends-with(preceding-sibling::node()[1]/self::text(), '\')
                                            or
                                            ends-with(preceding-sibling::node()[1]/self::*, '\')]" 
    mode="docx2hub:join-instrText-runs_render-compound3" >
    <xsl:apply-templates mode="#current"/>
  </xsl:template>
  
  <xsl:template match="dbk:wrapper/dbk:sep[ends-with(preceding-sibling::node()[1]/self::text(), '\')
                                           or
                                           ends-with(preceding-sibling::node()[1]/self::*, '\')]" 
    mode="docx2hub:join-instrText-runs_render-compound3" >
    <xsl:value-of select="':'"/>
  </xsl:template>

  <xsl:template match="node() | @*" mode="docx2hub:join-instrText-runs_render-compound3">
    <xsl:copy>
      <xsl:apply-templates select="@* | node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="dbk:wrapper" mode="docx2hub:join-instrText-runs_render-compound3">
    <xsl:apply-templates mode="#current"/>
  </xsl:template>

  
  <xsl:template match="m:oMath" mode="docx2hub:join-instrText-runs_render-compound2" priority="2">
    <xsl:sequence select="."/>
  </xsl:template>
  
  <xsl:template match="*:superscript | *:subscript" mode="docx2hub:join-instrText-runs_render-compound1 docx2hub:join-instrText-runs_render-compound2"
    priority="2">
    <xsl:copy>
      <xsl:apply-templates select="@*, node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <!--<xsl:template match="w:instrText[dbk:subscript | dbk:superscript]" 
    mode="docx2hub:join-instrText-runs_render-compound1 docx2hub:join-instrText-runs_render-compound2" priority="2">
    <xsl:sequence select="node()"/>
  </xsl:template>-->
  

  <xsl:template match="w:footnote/w:p[1][*[docx2hub:element-is-footnoteref(.)]]
                     | w:endnote/w:p[1][*[docx2hub:element-is-endnoteref(.)]]" mode="docx2hub:join-instrText-runs" priority="1">
    <xsl:variable name="prelim" as="document-node(element(*))">
      <xsl:document>
        <xsl:call-template name="docx2hub:first-note-para"/>
      </xsl:document>
    </xsl:variable>
    <!-- the current template won’t match on $prelim, therefore the template above, that matches *[w:r/w:instrText], 
      should match if there is w:instrText -->
    <xsl:apply-templates select="$prelim" mode="#current"/>
  </xsl:template>

  <!-- Making field function nesting explicit:
       – 'separate' and 'end' fldChars link to their 'begin' fldChar
       – the nesting level is given at each 'begin' fldChar, starting from 1 for the topmost nesting.
       If you experience performance issues/looping, try it with a Saxon PE license.
   -->
  <xsl:template match="document-node()[dbk:hub]" mode="docx2hub:join-instrText-runs">
    <xsl:variable name="nested-field-functions" as="document-node()">
      <xsl:call-template name="docx2hub:nest-field-functions">
        <xsl:with-param name="input">
          <xsl:document>
            <xsl:sequence select="//w:fldChar"/>
          </xsl:document>
        </xsl:with-param>
      </xsl:call-template>
    </xsl:variable>
    <xsl:next-match>
      <xsl:with-param name="nested-field-functions" select="$nested-field-functions" tunnel="yes"/>
    </xsl:next-match>
  </xsl:template>
  
  <!-- this happened in a previous mode: -->
  <xsl:template match="w:fldChar" mode="docx2hub:remove-redundant-run-atts">
    <xsl:copy copy-namespaces="no">
      <xsl:attribute name="xml:id" select="concat('fldChar_', generate-id())"/>
      <xsl:apply-templates select="@*, w:ffData/w:checkBox/w:default/@w:val" mode="#current"/>
      <!-- §17.16.17 for w:ffData -->
    </xsl:copy>    
  </xsl:template>
  
  <!-- also in a previous mode, remove w:lastRenderedPageBreak as it may be in
  runs that otherwise contain w:instrText, preventing adjacent w:instrText runs from being merged -->
  <xsl:template match="w:lastRenderedPageBreak" mode="docx2hub:remove-redundant-run-atts"/>
  
  <xsl:template match="w:r[count(*) = 1][w:instrText[. = '\']]
                          [following-sibling::*[1]/self::w:r/w:instrText[matches(., '[&quot;&#x201c;-&#x201e;]')]]" 
                mode="docx2hub:remove-redundant-run-atts">
    <!-- https://redmine.le-tex.de/issues/12022 -->
    <xsl:copy>
      <xsl:apply-templates select="following-sibling::*[1]/(@css:* | @xml:lang | @docx2hub:*)" mode="#current"/>
      <xsl:apply-templates select="@*[not(matches(name(), '^(css:|xml:lang|docx2hub)'))], node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template name="docx2hub:nest-field-functions" as="document-node()">
    <xsl:param name="input" as="document-node()"/><!-- containing raw w:fldChar or nested docx2hub:field-function -->
    <xsl:param name="iteration" as="xs:integer" select="1"/>
    <xsl:if test="$iteration gt 100">
      <xsl:message terminate="yes" select="'docx2hub:nest-field-functions may be looping. Input: ', $input"/>
    </xsl:if>
    <xsl:variable name="grouping" as="element(*)*">
      <xsl:for-each-group select="$input/*" 
                          group-starting-with="w:fldChar[@w:fldCharType = 'begin']
                                                        [following-sibling::w:fldChar[1]/@w:fldCharType = 'separate']
                                                        [following-sibling::w:fldChar[2]/@w:fldCharType = 'end']
                                               | 
                                               w:fldChar[@w:fldCharType = 'begin']
                                                        [following-sibling::w:fldChar[1]/@w:fldCharType = 'end']">
        <xsl:choose>
          <xsl:when test="self::w:fldChar[@w:fldCharType = 'begin']
                                         [following-sibling::w:fldChar[1]/@w:fldCharType = 'separate']
                                         [following-sibling::w:fldChar[2]/@w:fldCharType = 'end']
                          |
                          self::w:fldChar[@w:fldCharType = 'begin']
                                         [following-sibling::w:fldChar[1]/@w:fldCharType = 'end']">
            <xsl:variable name="end" as="element(w:fldChar)" 
              select="self::w:fldChar[@w:fldCharType = 'begin']
                              /following-sibling::w:fldChar[position() = (1, 2)][@w:fldCharType = 'end'][1]"/>
            <docx2hub:field-function>
              <xsl:apply-templates select="current-group()[. &lt;&lt; $end] union $end" mode="#current">
                <xsl:with-param name="begin" as="element(w:fldChar)" select="." tunnel="yes"/>
              </xsl:apply-templates>
            </docx2hub:field-function>
            <xsl:apply-templates select="current-group()[. &gt;&gt; $end]" mode="#current"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:apply-templates select="current-group()" mode="#current"/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each-group>
    </xsl:variable>
    <xsl:choose>
      <xsl:when test="count($grouping) = count($input/*)">
        <xsl:document>
          <xsl:sequence select="$grouping"/>
        </xsl:document>
      </xsl:when>
      <xsl:otherwise>
        <xsl:call-template name="docx2hub:nest-field-functions">
          <xsl:with-param name="input">
            <xsl:document>
              <xsl:sequence select="$grouping"/>
            </xsl:document>
          </xsl:with-param>
          <xsl:with-param name="iteration" select="$iteration + 1"/>
        </xsl:call-template>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  
  <xsl:template match="w:fldChar[@w:fldCharType = ('separate', 'end')]/@xml:id" mode="docx2hub:join-instrText-runs">
    <!-- $begin is present while the field functions are nested, detached from their original context: --> 
    <xsl:param name="begin" as="element(w:fldChar)?" tunnel="yes"/>
    <!-- $nested-field-functions is present when the complete document is processed (after xsl:next-match for /),
      adding the nesting info (@linkend that points to the begin fldChar) to the separate/end fldChars: --> 
    <xsl:param name="nested-field-functions" as="document-node()?" tunnel="yes"/>
    <xsl:copy/>
    <xsl:if test="exists($begin)">
      <xsl:attribute name="linkend" select="$begin/@xml:id"/>
    </xsl:if>
    <xsl:if test="exists($nested-field-functions)">
      <xsl:variable name="corresponding-item-in-nesting" as="element(w:fldChar)" 
        select="key('docx2hub:item-by-id', ., $nested-field-functions)"/>
      <xsl:sequence select="$corresponding-item-in-nesting/@linkend"/>
      <xsl:attribute name="level" select="count($corresponding-item-in-nesting/ancestor::docx2hub:field-function)"/>
    </xsl:if>
  </xsl:template>
  
  <!-- determine whether inline or display equation -->
  
  <xsl:template match="dbk:inlineequation[@role eq 'mtef']" mode="docx2hub:join-runs">
    <xsl:variable name="para" select="ancestor::dbk:para[1]" as="element(dbk:para)"/>
    <xsl:variable name="is-display-equation" select="docx2hub:is-display-equation(.)" as="xs:boolean"/>
    <xsl:element name="{if ($is-display-equation) then 'equation' else name()}">
      <xsl:if test="$is-display-equation">
        <!-- also consider other inline parent elements? This was done solely on the example given
          in https://github.com/transpect/docx2hub/issues/23 -->
        <xsl:apply-templates select="parent::dbk:phrase/(@css:* | @xml:*)"/>
      </xsl:if>
      <xsl:apply-templates select="@*, node()" mode="#current"/>
    </xsl:element>
  </xsl:template>
  
  <xsl:function name="docx2hub:is-display-equation" as="xs:boolean">
    <xsl:param name="ieq" as="element(*)"/>
    <xsl:variable name="para" as="element(dbk:para)" select="$ieq/ancestor::dbk:para[1]"/>
    <xsl:sequence 
      select="exists($ieq/self::dbk:inlineequation)
              and
              count($para//dbk:inlineequation[dbk:same-scope($ieq, $para)]) eq 1
              and 
              not(
                normalize-space(
                  string-join(
                    $para//text()[dbk:same-scope(., $para)]
                                 [empty(ancestor::dbk:phrase[@role = 'hub:equation-number'])]
                                 [namespace-uri(..) ne 'http://www.w3.org/1998/Math/MathML'],
                    ''
                  )
                )
              )"/>
  </xsl:function>
  
<!-- group more than one mml:mi[@mathvariant='normal'] element to mtext; exclude mathtype2mml processed mathml -->
  <xsl:template match="mml:*[not(ancestor::*[ends-with(name(), 'equation')]/@role eq 'mtef')][mml:mi]" mode="docx2hub:join-runs">
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:for-each-group select="node()" group-adjacent="exists(self::mml:mi[@mathvariant eq 'normal'] 
                                                                |self::mml:mtext[not(@fontstyle or @fontweight) or (@fontstyle, @fontweight) = 'normal'])">
        <xsl:choose>
          <xsl:when test="current-grouping-key() and string-length(string-join(current-group(), '')) gt 1">
            <xsl:for-each-group select="current-group()" group-adjacent="if (@mathcolor) then @mathcolor else ''">
              <xsl:choose>
                <xsl:when test="string-length(string-join(current-group(), '')) gt 1">
                  <xsl:variable name="prelim" as="element(mml:mtext)">
                    <mml:mtext>
                      <xsl:apply-templates select="current-group()[1]/@*[not(name() = 'fontstyle')]" mode="#current"/>
                      <xsl:apply-templates select="current-group()/node()" mode="#current"/>
                    </mml:mtext>  
                  </xsl:variable>
                  <xsl:apply-templates select="$prelim" mode="#current"/>    
                </xsl:when>
                <xsl:otherwise>
                  <xsl:apply-templates select="current-group()" mode="#current"/>
                </xsl:otherwise>
              </xsl:choose>
            </xsl:for-each-group>
          </xsl:when>
          <xsl:otherwise>
            <xsl:apply-templates select="current-group()" mode="#current"/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each-group>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="mml:mtext | mml:mi[child::text()[matches(.,'^\s+$')] and not(child::*)]" mode="docx2hub:join-runs">
    <xsl:call-template name="mtext-or-mspace">
      <xsl:with-param name="string" as="xs:string" select="."/>
    </xsl:call-template>
  </xsl:template>
  
  <xsl:variable name="opening-parenthesis" select="('[', '{', '(')" as="xs:string*"/>
  <xsl:variable name="closing-parenthesis" select="(']', '}', ')')" as="xs:string*"/>
  
  <xsl:template match="mml:mrow[$mml-version ne '4-core']
                               [count(*) = 3]
                               [*[1]/self::mml:mo = $opening-parenthesis]
                               [*[3]/self::mml:mo = $closing-parenthesis]" mode="docx2hub:join-runs" priority="1">
    <mml:mfenced open="{*[1]}" close="{*[3]}" separators="">
      <xsl:apply-templates select="if(*[2]/self::mml:mrow) then *[2]/node() else *[2]" mode="#current"/>
    </mml:mfenced>
  </xsl:template>
  
    <!-- resolve border-conflicts -->
  <xsl:template match="dbk:informaltable[@css:border-collapse = 'separate']" mode="docx2hub:join-runs">
    <xsl:variable name="curr" select="."/>
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:for-each select="('left', 'right', 'top', 'bottom')">
        <xsl:variable name="border-prefix" select="concat('border-', .)"/>
        <xsl:variable name="table-border-styles" select="$curr/@css:*[matches(local-name(), $border-prefix)]"/>
        <xsl:choose>
          <xsl:when test="$table-border-styles">
            <xsl:apply-templates select="$table-border-styles" mode="#current"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:attribute name="css:{$border-prefix}-style" select="'none'"/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <!-- remove empty paras in headers and footers -->
  
  <xsl:template match="dbk:div[@role = ('docx2hub:header', 'docx2hub:footer')]/dbk:para[not(node())]" mode="docx2hub:join-runs"/>
  
<!--  <xsl:template match="dbk:informaltable[@css:border-collapse = 'collapse']" mode="docx2hub:join-runs">
    <xsl:variable name="curr" select="." as="element()"/>
    <xsl:variable name="css-rule" select="//css:rule[@name = $curr/@role]" as="element()*"/>
    <xsl:variable name="cols" select="dbk:tgroup[1]/@cols" as="xs:decimal"/>
    <xsl:variable name="colspecs" select="$curr/dbk:tgroup/dbk:colspec"/>
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@* except @css:*[matches(local-name(), '^border-(left|right|top|bottom)')]" mode="#current"/>
      <xsl:for-each select="('left', 'right', 'top', 'bottom')">
        <xsl:variable name="border-prefix" select="concat('border-', .)"/>
        <xsl:variable name="cell-borders" select="
          (
            $curr[current() = 'left']//dbk:entry[calstable:in-first-col(., $colspecs)],
            $curr[current() = 'right']//dbk:entry[calstable:in-last-col(., $colspecs)],
            $curr[current() = 'top']//dbk:row[1]/dbk:entry,
            $curr[current() = 'bottom']//dbk:entry[not(calstable:entry-overlaps(., following::dbk:entry[ancestor::node()/generate-id() = $curr/generate-id()], $colspecs))]
          )/@css:*[matches(local-name(), $border-prefix)]" as="attribute()*">
        </xsl:variable>
        <xsl:variable name="cell-border-styles" select="$cell-borders[matches(local-name(), 'style$')]"/>
        <xsl:variable name="table-border-styles" select="$curr/@css:*[matches(local-name(), $border-prefix)]"/>
        <xsl:choose>
          <xsl:when test="count(distinct-values($cell-border-styles)) gt 1">
            <xsl:attribute name="css:{$border-prefix}-style" select="'none'"/>
          </xsl:when>
          <xsl:when test="not('inherit' = $cell-border-styles)">
            <xsl:apply-templates select="$cell-borders" mode="#current">
              <xsl:sort/>
            </xsl:apply-templates>
          </xsl:when>
          <xsl:when test="$table-border-styles">
            <xsl:apply-templates select="$table-border-styles" mode="#current"/>
          </xsl:when>
          <xsl:when test="$curr/@role">
            <xsl:apply-templates select="$css-rule/@css:*[matches(local-name(), $border-prefix)]" mode="#current"/>
          </xsl:when>
          <xsl:otherwise>
            <xsl:attribute name="css:{$border-prefix}-style" select="'none'"/>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="
    dbk:informaltable[@css:border-collapse = 'collapse']//dbk:entry" mode="docx2hub:join-runs">
    <!-\- context will change multiple times, so keep references to nodes which are findable now (but nearly impossible later on) -\->
    <xsl:variable name="curr" select="." as="element()"/>
    <xsl:variable name="colspecs" select="ancestor::dbk:tgroup[1]/dbk:colspec" as="element()+"/>
    <xsl:variable name="table-atts" select="ancestor::dbk:informaltable/@css:*[matches(local-name(), 'border-')]" as="attribute()*"/>
    <!-\-<xsl:variable name="is-last-row-thead"
      select="parent::dbk:row/parent::dbk:thead and
      calstable:entry-overlaps(., (following-sibling::dbk:entry, parent::dbk:row/following-sibling::dbk:row/dbk:entry), $colspecs)"
      as="xs:boolean"/>
    <xsl:variable name="last-thead-atts"
      select="ancestor::node()[3][$is-last-row-thead]/dbk:tbody/dbk:row[1]/dbk:entry/@css:*[matches(local-name(), 'border-top')]"
      as="attribute()*"/>-\->
    <xsl:variable name="preceding-entries"
      select="preceding::dbk:entry[ancestor::dbk:informaltable = current()/ancestor::dbk:informaltable]" as="element()*"
    />
    <xsl:variable name="following-entries"
      select="following::dbk:entry[ancestor::dbk:informaltable = current()/ancestor::dbk:informaltable]" as="element()*"
    />
    <xsl:copy copy-namespaces="no">
      <xsl:apply-templates select="@* except @css:*[matches(local-name(), '^border-(left|right|top|bottom)')]" mode="#current"/>
      <xsl:for-each select="('left', 'right', 'top', 'bottom')">
        <xsl:variable name="border-prefix" select="concat('border-', .)" as="xs:string"/>
        <xsl:variable name="inherit-table-border"
          select="$curr/@css:*[matches(local-name(), concat($border-prefix, '-style$'))] = 'inherit'" as="xs:boolean"/>
        <xsl:variable name="cell-border-atts" select="$curr/@css:*[matches(local-name(), $border-prefix)]" as="attribute()*"/>
        <xsl:variable name="table-border-atts"
          select="$table-atts[matches(local-name(), $border-prefix)]" as="attribute()*"/>
        <xsl:apply-templates
          select="$table-border-atts[$inherit-table-border], $cell-border-atts[not($inherit-table-border and $table-border-atts)]"
          mode="#current"/>
      </xsl:for-each>
      <xsl:apply-templates select="node()" mode="#current"/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="@css:*[matches(local-name(), '^border-(left|right|top|bottom)-style$')][. = 'inherit']" mode="docx2hub:join-runs">
    <xsl:attribute name="{name()}" select="'none'"/>
  </xsl:template>-->

  <xsl:template match="*[dbk:imageobject/dbk:imagedata/@role = 'hub:linked']
                        /dbk:imageobject[dbk:imagedata/@role = 'hub:embedded']" mode="docx2hub:join-runs">
    <imageobject>
      <xsl:apply-templates select="@*, node()" mode="#current"/>
      <xsl:apply-templates select="../dbk:imageobject/dbk:imagedata[@role = 'hub:linked']" mode="#current"/>
    </imageobject>
  </xsl:template>
  <xsl:template match="*[dbk:imageobject/dbk:imagedata/@role = 'hub:embedded']
                        /dbk:imageobject[dbk:imagedata/@role = 'hub:linked']" mode="docx2hub:join-runs"/>
  <xsl:template match="*[not(dbk:imageobject/dbk:imagedata/@role = 'hub:embedded')]
                        /dbk:imageobject/dbk:imagedata/@role[. = 'hub:linked']" mode="docx2hub:join-runs"/>


  <!-- collateral: optionally convert double-struck, fraktur and script mathvariants to Unicode characters.
       This is not exactly a heuristic replacement, but we are using this existing option for reasons of
       parsimony (we don’t want to introduce a new option). This replacement, however, may not be activated
       by using the #all or #formulas keywords. It needs to be activated by a token of its own, 'exotic-mathvariants'. 
  
      Word’s equation editor seems to export U+2118 not as P with mathvariant script but as U+2118 with either
      no mathvariant, matchvariant=double-struck or mathvariant=script. Therefore there is a special treatment
      for &#x2118; below.
  -->

  <xsl:template match="mml:mi[$heuristic-character-replacement-tokens = 'exotic-mathvariants']
                             [tokenize(@mathvariant, '\s+') = 'double-struck']" mode="docx2hub:join-runs">
    <xsl:variable name="context" as="element(mml:mi)" select="."/>
    <xsl:variable name="other-variants" as="xs:string*" select="tokenize(@mathvariant, '\s+')[not(. = 'double-struck')]"/>
    <xsl:copy>
      <xsl:apply-templates select="@* except @mathvariant" mode="#current"/>
      <xsl:if test="exists($other-variants)">
        <xsl:attribute name="mathvariant" select="$other-variants" separator=" "/>
      </xsl:if>
      <xsl:analyze-string select="." regex="[A-Za-z&#x2118;]">
        <xsl:matching-substring>
          <xsl:choose>
            <xsl:when test=". = 'C'">&#x2102;</xsl:when>
            <xsl:when test=". = 'H'">&#x210D;</xsl:when>
            <xsl:when test=". = 'N'">&#x2115;</xsl:when>
            <xsl:when test=". = 'P'">&#x2119;</xsl:when>
            <xsl:when test=". = 'Q'">&#x211A;</xsl:when>
            <xsl:when test=". = 'R'">&#x211D;</xsl:when>
            <xsl:when test=". = 'Z'">&#x2124;</xsl:when>
            <xsl:when test=". = '℘'">&#x2118;</xsl:when>
            <xsl:when test="matches(., '^[A-Z]$')">
              <xsl:value-of select="codepoints-to-string(120055 + string-to-codepoints(.))"/>
            </xsl:when>
            <xsl:when test="matches(., '^[a-z]$')">
              <xsl:value-of select="codepoints-to-string(120049 + string-to-codepoints(.))"/>
            </xsl:when>
          </xsl:choose>    
        </xsl:matching-substring>
        <xsl:non-matching-substring>
          <xsl:sequence select="docx2hub:message($context, $fail-on-error = 'yes', false(), 'W2D_621', 'ERR', 'docx2hub:join-runs', 
                                                   concat('No mapping for double-struck character(s) ', .) 
                                                   )"/>
          <xsl:value-of select="."/>
        </xsl:non-matching-substring>
      </xsl:analyze-string>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="mml:mi[$heuristic-character-replacement-tokens = 'exotic-mathvariants']
                             [tokenize(@mathvariant, '\s+') = 'fraktur']" mode="docx2hub:join-runs">
    <xsl:variable name="context" as="element(mml:mi)" select="."/>
    <xsl:variable name="other-variants" as="xs:string*" select="tokenize(@mathvariant, '\s+')[not(. = 'fraktur')]"/>
    <xsl:copy>
      <xsl:apply-templates select="@* except @mathvariant" mode="#current"/>
      <xsl:if test="exists($other-variants)">
        <xsl:attribute name="mathvariant" select="$other-variants" separator=" "/>
      </xsl:if>
      <xsl:analyze-string select="." regex="[A-Za-z]">
        <xsl:matching-substring>
          <xsl:choose>
            <xsl:when test=". = 'C'">&#x212D;</xsl:when>
            <xsl:when test=". = 'H'">&#x210C;</xsl:when>
            <xsl:when test=". = 'I'">&#x2111;</xsl:when>
            <xsl:when test=". = 'R'">&#x211C;</xsl:when>
            <xsl:when test=". = 'Z'">&#x2128;</xsl:when>
            <xsl:when test="matches(., '^[A-Z]$')">
              <xsl:value-of select="codepoints-to-string(120003 + string-to-codepoints(.))"/>
            </xsl:when>
            <xsl:when test="matches(., '^[a-z]$')">
              <xsl:value-of select="codepoints-to-string(119997 + string-to-codepoints(.))"/>
            </xsl:when>
          </xsl:choose>    
        </xsl:matching-substring>
        <xsl:non-matching-substring>
          <xsl:sequence select="docx2hub:message($context, $fail-on-error = 'yes', false(), 'W2D_622', 'ERR', 'docx2hub:join-runs', 
                                                   concat('No mapping for fraktur character(s) ', .) 
                                                   )"/>
          <xsl:value-of select="."/>
        </xsl:non-matching-substring>
      </xsl:analyze-string>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="mml:mi[$heuristic-character-replacement-tokens = 'exotic-mathvariants']
                             [tokenize(@mathvariant, '\s+') = 'bold-fraktur']" mode="docx2hub:join-runs">
    <xsl:variable name="context" as="element(mml:mi)" select="."/>
    <xsl:variable name="other-variants" as="xs:string*" select="tokenize(@mathvariant, '\s+')[not(. = 'bold-fraktur')]"/>
    <xsl:copy>
      <xsl:apply-templates select="@* except @mathvariant" mode="#current"/>
      <xsl:if test="exists($other-variants)">
        <xsl:attribute name="mathvariant" select="$other-variants" separator=" "/>
      </xsl:if>
      <xsl:analyze-string select="." regex="[A-Za-z]">
        <xsl:matching-substring>
          <xsl:choose>
            <xsl:when test="matches(., '^[A-Z]$')">
              <xsl:value-of select="codepoints-to-string(120107 + string-to-codepoints(.))"/>
            </xsl:when>
            <xsl:when test="matches(., '^[a-z]$')">
              <xsl:value-of select="codepoints-to-string(120101 + string-to-codepoints(.))"/>
            </xsl:when>
          </xsl:choose>    
        </xsl:matching-substring>
        <xsl:non-matching-substring>
          <xsl:sequence select="docx2hub:message($context, $fail-on-error = 'yes', false(), 'W2D_623', 'ERR', 'docx2hub:join-runs', 
                                                   concat('No mapping for bold-fraktur character(s) ', .) 
                                                   )"/>
          <xsl:value-of select="."/>
        </xsl:non-matching-substring>
      </xsl:analyze-string>
    </xsl:copy>
  </xsl:template>

  <xsl:template match="mml:mi[$heuristic-character-replacement-tokens = 'exotic-mathvariants']
                             [tokenize(@mathvariant, '\s+') = 'script']" mode="docx2hub:join-runs">
    <xsl:variable name="context" as="element(mml:mi)" select="."/>
    <xsl:variable name="other-variants" as="xs:string*" select="tokenize(@mathvariant, '\s+')[not(. = 'script')]"/>
    <xsl:copy>
      <xsl:apply-templates select="@* except @mathvariant" mode="#current"/>
      <xsl:if test="exists($other-variants)">
        <xsl:attribute name="mathvariant" select="$other-variants" separator=" "/>
      </xsl:if>
      <xsl:analyze-string select="." regex="[A-Za-z&#x2118;]">
        <xsl:matching-substring>
          <xsl:choose>
            <xsl:when test=". = 'B'">&#x212C;</xsl:when>
            <xsl:when test=". = 'E'">&#x2130;</xsl:when>
            <xsl:when test=". = 'F'">&#x2131;</xsl:when>
            <xsl:when test=". = 'H'">&#x210B;</xsl:when>
            <xsl:when test=". = 'I'">&#x2110;</xsl:when>
            <xsl:when test=". = 'L'">&#x2112;</xsl:when>
            <xsl:when test=". = 'M'">&#x2133;</xsl:when>
            <xsl:when test=". = 'R'">&#x211B;</xsl:when>
            <xsl:when test=". = 'e'">&#x212F;</xsl:when>
            <xsl:when test=". = 'g'">&#x210A;</xsl:when>
            <xsl:when test=". = 'o'">&#x2134;</xsl:when>
            <xsl:when test=". = '℘'">&#x2118;</xsl:when>
            <xsl:when test="matches(., '^[A-Z]$')">
              <xsl:value-of select="codepoints-to-string(119899 + string-to-codepoints(.))"/>
            </xsl:when>
            <xsl:when test="matches(., '^[a-z]$')">
              <xsl:value-of select="codepoints-to-string(119893 + string-to-codepoints(.))"/>
            </xsl:when>
          </xsl:choose>    
        </xsl:matching-substring>
        <xsl:non-matching-substring>
          <xsl:sequence select="docx2hub:message($context, $fail-on-error = 'yes', false(), 'W2D_624', 'ERR', 'docx2hub:join-runs', 
                                                   concat('No mapping for script character(s) ', .) 
                                                   )"/>
          <xsl:value-of select="."/>
        </xsl:non-matching-substring>
      </xsl:analyze-string>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="mml:mi[$heuristic-character-replacement-tokens = 'exotic-mathvariants']
                             [tokenize(@mathvariant, '\s+') = 'bold-script']" mode="docx2hub:join-runs">
    <xsl:variable name="context" as="element(mml:mi)" select="."/>
    <xsl:variable name="other-variants" as="xs:string*" select="tokenize(@mathvariant, '\s+')[not(. = 'bold-script')]"/>
    <xsl:copy>
      <xsl:apply-templates select="@* except @mathvariant" mode="#current"/>
      <xsl:if test="exists($other-variants)">
        <xsl:attribute name="mathvariant" select="$other-variants" separator=" "/>
      </xsl:if>
      <xsl:analyze-string select="." regex="[A-Za-z]">
        <xsl:matching-substring>
          <xsl:choose>
            <xsl:when test="matches(., '^[A-Z]$')">
              <xsl:value-of select="codepoints-to-string(119951 + string-to-codepoints(.))"/>
            </xsl:when>
            <xsl:when test="matches(., '^[a-z]$')">
              <xsl:value-of select="codepoints-to-string(119945 + string-to-codepoints(.))"/>
            </xsl:when>
          </xsl:choose>    
        </xsl:matching-substring>
        <xsl:non-matching-substring>
          <xsl:sequence select="docx2hub:message($context, $fail-on-error = 'yes', false(), 'W2D_625', 'ERR', 'docx2hub:join-runs', 
                                                   concat('No mapping for bold-script character(s) ', .) 
                                                   )"/>
          <xsl:value-of select="."/>
        </xsl:non-matching-substring>
      </xsl:analyze-string>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="mml:mi[$heuristic-character-replacement-tokens = 'exotic-mathvariants']
                             [tokenize(@mathvariant, '\s+') = ('initial', 'looped', 'tailed', 'stretched')]" mode="docx2hub:join-runs">
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:sequence select="docx2hub:message(., $fail-on-error = 'yes', false(), 'W2D_626', 'ERR', 'docx2hub:join-runs', 
                                                   concat('No mapping for ', @mathvariant, ' character(s) ', .) 
                                                   )"/>
      <xsl:value-of select="."/>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template match="dbk:tgroup[$normalize-thead='yes'][dbk:thead//dbk:entry[@morerows ne '0']]" mode="docx2hub:join-runs">
    <xsl:copy>
      <xsl:apply-templates select="@*" mode="#current"/>
      <xsl:apply-templates select="node() except (dbk:thead,dbk:tbody)" mode="#current"/>
      <xsl:choose>
        <xsl:when test="tr:check-for-morerows(dbk:thead/dbk:row)">
          <xsl:call-template name="check-body-rows">
            <xsl:with-param name="tbody" select="dbk:tbody/dbk:row"/>
            <xsl:with-param name="thead" select="dbk:thead/dbk:row"/>
            <xsl:with-param name="count" select="tr:count-morerows(dbk:thead/dbk:row)">
            </xsl:with-param>
          </xsl:call-template>
        </xsl:when>
        <xsl:otherwise>
          <xsl:apply-templates select="dbk:thead|dbk:tbody" mode="#current"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:copy>
  </xsl:template>
  
  <xsl:template name="check-body-rows">
    <xsl:param name="tbody" as="node() *"/>
    <xsl:param name="thead" as="node() *"/>
    <xsl:param name="count" as="xs:double"/>
    
    <xsl:variable name="new_thead">
      <xsl:sequence select="$thead"/>
      <xsl:sequence select="$tbody[position() lt ($count + 1)]" />
    </xsl:variable>
    
    <xsl:choose>
      <xsl:when test="count($tbody) lt $count">
        <xsl:processing-instruction name="letex" select="'D2T_010: Fehlerhaftes Attribut (morerows erstreckt sich über Ende des tbody)'"/>
        <thead>
          <xsl:apply-templates select="$new_thead" mode="#current"/>
        </thead>
        <tbody>
          <xsl:apply-templates select="$tbody[position() gt $count]" mode="#current"/>
        </tbody>
      </xsl:when>
      <xsl:when test="tr:check-for-morerows($new_thead)">
        <xsl:call-template name="check-body-rows">
          <xsl:with-param name="tbody" select="$tbody[position() gt $count]"/>
          <xsl:with-param name="thead" select="$new_thead"/>
          <xsl:with-param name="count" select="tr:count-morerows($new_thead)">
          </xsl:with-param>
        </xsl:call-template>
      </xsl:when>
      <xsl:otherwise>
        <thead>
          <xsl:apply-templates select="$new_thead" mode="#current"/>
        </thead>
        <xsl:if test="count($tbody[position() gt $count]) gt 0">
          <tbody>
            <xsl:apply-templates select="$tbody[position() gt $count]" mode="#current"/>
          </tbody>
        </xsl:if>
      </xsl:otherwise>
    </xsl:choose>
    
  </xsl:template>

  <xsl:function name="tr:count-morerows">
    <xsl:param name="input-rows"/>
    
    <xsl:variable name="count_rows" as="xs:double *">
      <xsl:for-each select="$input-rows/descendant::dbk:entry[@morerows ne '0']">
        <xsl:sequence select="@morerows - count(parent::dbk:row/following-sibling::dbk:row)"/>
      </xsl:for-each>
    </xsl:variable>
    <xsl:copy-of select="max($count_rows)"/>
    
  </xsl:function>
  
  <xsl:function name="tr:check-for-morerows">
    <xsl:param name="input-rows"/>
    
    <xsl:variable name="missing_rows" select="if (some $x in $input-rows/descendant::dbk:entry[@morerows ne '0'] satisfies (($x/@morerows - count($x/parent::dbk:row/following-sibling::dbk:row)) gt 0)) then true() else false()" />
    <xsl:copy-of select="$missing_rows"/>
    
  </xsl:function>

</xsl:stylesheet>
