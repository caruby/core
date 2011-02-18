package clinicaltrials.domain;

public class Consent extends DomainObject
{
    /**
     * The offset from the beginning of the study.
     */
    private String statement;

    public Consent()
    {
    }

    /**
     * @return the statement
     */
    public String getStatement()
    {
        return statement;
    }

    /**
     * @param statement the value to set
     */
    public void setStatement(String statement)
    {
        this.statement = statement;
    }
}
